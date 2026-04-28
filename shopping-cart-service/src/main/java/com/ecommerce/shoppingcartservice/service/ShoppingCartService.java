package com.ecommerce.shoppingcartservice.service;

import com.ecommerce.shoppingcartservice.model.AddItemResult;
import com.ecommerce.shoppingcartservice.model.CartItem;
import com.ecommerce.shoppingcartservice.model.CheckoutResult;
import com.ecommerce.shoppingcartservice.model.ShipMessage;
import com.ecommerce.shoppingcartservice.model.ShoppingCart;
import java.util.ArrayList;
import java.util.List;
import java.util.Optional;
import java.util.concurrent.ThreadLocalRandom;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.amqp.rabbit.core.RabbitTemplate;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

/**
 * Core business logic for the Shopping Cart service.
 * <p>
 * Checkout transaction boundary (as required by Assignment 5):
 * <p>
 *   begin_transaction
 *       │
 *       ├─► Reserve inventory per item ─── FAIL ──► abort_transaction → "Out of Stock"
 *       │           │ SUCCESS
 *       ├─► Authorize credit card ──────── DECLINE ► abort_transaction + unreserve → "Payment Declined"
 *       │           │ SUCCESS
 *       ├─► Commit order to KV database
 *       │
 *   end_transaction
 *       │
 *       └─► Publish ship messages to RabbitMQ (async, fire-and-forget, outside transaction)
 */
@Service
public class ShoppingCartService {

  private static final Logger log = LoggerFactory.getLogger(ShoppingCartService.class);

  private final KvDatabaseClient kvClient;
  private final WarehouseServiceClient warehouseServiceClient;
  private final ProductServiceClient productServiceClient;
  private final CreditCardAuthorizerServiceClient creditCardAuthorizerServiceClient;
  private final RabbitTemplate rabbitTemplate;

  @Value("${warehouse.queue.name}")
  private String shipQueueName;

  public ShoppingCartService(KvDatabaseClient kvClient,
      WarehouseServiceClient warehouseServiceClient, ProductServiceClient productServiceClient,
      CreditCardAuthorizerServiceClient creditCardAuthorizerServiceClient,
      RabbitTemplate rabbitTemplate) {
    this.kvClient = kvClient;
    this.warehouseServiceClient = warehouseServiceClient;
    this.productServiceClient = productServiceClient;
    this.creditCardAuthorizerServiceClient = creditCardAuthorizerServiceClient;
    this.rabbitTemplate = rabbitTemplate;
  }

  // ── Create cart ───────────────────────────────────────────────────────────

  /**
   * Creates a new cart with a random int ID. Collision probability is negligible at this
   * assignment's scale, and unlike AtomicInteger, this is safe across multiple auto-scaled
   * instances.
   */
  public int createCart(int customerId) {
    int cartId = ThreadLocalRandom.current().nextInt(1, Integer.MAX_VALUE);
    ShoppingCart cart = new ShoppingCart(cartId, customerId, new ArrayList<>());
    kvClient.saveCart(cart);
    kvClient.saveActiveCartId(customerId, cartId);
    return cartId;
  }

  // ── Add item ──────────────────────────────────────────────────────────────

  /**
   * Adds an item to the customer's active cart.
   * <p>
   * Assignment 5 requires add-to-cart to work against the active cart for a customer and create
   * one when none exists. Validation runs before the cart is resolved so invalid product IDs or
   * out-of-stock requests do not create an empty cart as a side effect.
   */
  public AddItemResult addItem(int customerId, int productId, int quantity) {
    if (quantity > 10_000) {
      return AddItemResult.badRequest("quantity must be at most 10000");
    }

    int weight = productServiceClient.getProductWeight(productId);
    if (weight < 0) {
      return AddItemResult.notFound("Product not found: " + productId);
    }

    int available = warehouseServiceClient.checkInventory(productId);
    if (available < quantity) {
      return AddItemResult.insufficientStock(
          "Insufficient inventory for product " + productId + ": requested=" + quantity
              + " available=" + available);
    }

    int cartId = getOrCreateActiveCartId(customerId);
    Optional<ShoppingCart> cartOpt = kvClient.getCart(cartId);
    if (cartOpt.isEmpty()) {
      return AddItemResult.notFound("Shopping cart not found: " + cartId);
    }

    ShoppingCart cart = cartOpt.get();
    addItemToLoadedCart(cart, productId, quantity, weight);
    return AddItemResult.ok(cart.getCart_id());
  }

  /**
   * Mutates a cart that has already been loaded and validated, merging quantity when the product is
   * already present and persisting the updated cart back to KV storage.
   */
  private void addItemToLoadedCart(ShoppingCart cart, int productId, int quantity, int weight) {
    // Add to existing item if product already in cart, otherwise append
    boolean found = false;
    for (CartItem item : cart.getItems()) {
      if (item.getProduct_id() == productId) {
        item.setQuantity(item.getQuantity() + quantity);
        item.setWeight(item.getWeight() + weight * quantity);
        found = true;
        break;
      }
    }
    if (!found) {
      cart.getItems().add(new CartItem(productId, quantity, weight * quantity));
    }

    kvClient.saveCart(cart);
  }

  /**
   * Returns the customer's current active cart ID, creating a new cart if none exists.
   * <p>
   * If the active-cart mapping points to a missing cart, treat it as stale metadata, log it, and
   * recreate the cart so add-to-cart remains self-healing.
   */
  private int getOrCreateActiveCartId(int customerId) {
    Optional<Integer> cartIdOpt = kvClient.getActiveCartId(customerId);
    if (cartIdOpt.isPresent()) {
      int cartId = cartIdOpt.get();
      if (kvClient.getCart(cartId).isPresent()) {
        return cartId;
      }
      log.warn("Active cart mapping is stale for customer {}: cart {} not found. Recreating cart.",
          customerId, cartId);
    }
    return createCart(customerId);
  }

  // ── Checkout ──────────────────────────────────────────────────────────────

  /**
   * Processes a full checkout, including transaction boundary calls, inventory reservation, payment
   * authorization, order commit, and async shipment dispatch.
   * <p>
   * Fix: track whether the transaction has been committed before deciding to abort in the exception
   * handler — calling abort_transaction after end_transaction is wrong. Fix: publishShipment is now
   * fire-and-forget (no blocking confirm wait) and runs outside the try block so a publish failure
   * cannot trigger a spurious abort.
   */
  public CheckoutResult checkout(int cartId, String creditCardNumber) {
    Optional<ShoppingCart> cartOpt = kvClient.getCart(cartId);
    if (cartOpt.isEmpty()) {
      return CheckoutResult.notFound("Shopping cart not found: " + cartId);
    }
    ShoppingCart cart = cartOpt.get();
    if (cart.getItems().isEmpty()) {
      return CheckoutResult.badRequest("Cannot checkout an empty cart");
    }

    String txId = kvClient.beginTransaction();
    List<CartItem> reservedItems = new ArrayList<>();
    boolean committed = false;
    int orderId = 0;

    try {
      // Step 1: Reserve inventory for each item
      for (CartItem item : cart.getItems()) {
        boolean reserved = warehouseServiceClient.reserve(item.getProduct_id(), item.getQuantity());
        if (!reserved) {
          kvClient.abortTransaction(txId);
          warehouseServiceClient.unreserveAll(reservedItems);
          return CheckoutResult.outOfStock(
              "Insufficient stock for product " + item.getProduct_id());
        }
        reservedItems.add(item);
      }

      // Step 2: Authorize credit card
      boolean authorized = creditCardAuthorizerServiceClient.authorize(creditCardNumber);
      if (!authorized) {
        kvClient.abortTransaction(txId);
        warehouseServiceClient.unreserveAll(reservedItems);
        return CheckoutResult.paymentDeclined("Payment declined");
      }

      // Step 3: Commit order to KV database
      orderId = kvClient.commitOrder(cart, creditCardNumber);
      kvClient.saveCart(
          new ShoppingCart(cart.getCart_id(), cart.getCustomer_id(), new ArrayList<>()));
      kvClient.clearActiveCart(cart.getCustomer_id());

      // Step 4: End transaction
      kvClient.endTransaction(txId);
      committed = true;

    } catch (Exception e) {
      log.error("Checkout failed for cart {}: {}", cartId, e.getMessage());
      if (!committed) {
        kvClient.abortTransaction(txId);
        warehouseServiceClient.unreserveAll(reservedItems);
      }
      throw e;
    }

    // Step 5: Publish ship message — fire-and-forget, outside transaction boundary.
    // A publish failure does not roll back the committed order; in a real system this
    // would be handled by an outbox pattern or dead-letter queue.
    try {
      rabbitTemplate.convertAndSend("", shipQueueName,
          new ShipMessage(orderId, new ArrayList<>(cart.getItems())));
    } catch (Exception e) {
      log.error("Ship message publish failed for order {} (order is committed): {}", orderId,
          e.getMessage());
    }

    log.info("Checkout complete: cart={} order={}", cartId, orderId);
    return CheckoutResult.success(orderId);
  }
}
