package com.ecommerce.shoppingcartservice.controller;

import com.ecommerce.common.util.SimulatedLoad;
import com.ecommerce.shoppingcartservice.model.AddItemRequest;
import com.ecommerce.shoppingcartservice.model.CheckoutRequest;
import com.ecommerce.shoppingcartservice.model.CreateCartRequest;
import com.ecommerce.shoppingcartservice.model.AddItemResult;
import com.ecommerce.shoppingcartservice.model.CheckoutResult;
import com.ecommerce.shoppingcartservice.service.ShoppingCartService;
import jakarta.validation.Valid;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ShoppingCartController {

  private final ShoppingCartService cartService;

  public ShoppingCartController(ShoppingCartService cartService) {
    this.cartService = cartService;
  }

  /**
   * Creates a new shopping cart for a customer and returns the assigned cart ID (UUID string).
   */
  @PostMapping("/shopping-cart")
  public ResponseEntity<Map<String, Integer>> createCart(
      @Valid @RequestBody CreateCartRequest request) {
    SimulatedLoad.busyWait(SimulatedLoad.logNormalDelayMs());
    int cartId = cartService.createCart(request.getCustomer_id());
    return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("shopping_cart_id", cartId));
  }

  /**
   * Adds a product to the customer's active cart, creating one if needed.
   * Returns 200 with shopping_cart_id on success, 404 if product not found, 409 if insufficient
   * stock.
   */
  @PostMapping("/shopping-carts/addItem")
  public ResponseEntity<?> addItem(
      @Valid @RequestBody AddItemRequest request) {
    SimulatedLoad.busyWait(SimulatedLoad.logNormalDelayMs());
    AddItemResult result = cartService.addItem(
        request.getCustomer_id(), request.getProduct_id(), request.getQuantity());

    if (result.status() == AddItemResult.Status.OK) {
      return ResponseEntity.ok(Map.of("shopping_cart_id", result.cartId()));
    } else if (result.status() == AddItemResult.Status.BAD_REQUEST) {
      return ResponseEntity.badRequest()
          .body(Map.of("error", "INVALID_INPUT", "message", result.message()));
    } else if (result.status() == AddItemResult.Status.NOT_FOUND) {
      return ResponseEntity.status(HttpStatus.NOT_FOUND)
          .body(Map.of("error", "NOT_FOUND", "message", result.message()));
    } else {
      return ResponseEntity.status(HttpStatus.CONFLICT)
          .body(Map.of("error", "INSUFFICIENT_STOCK", "message", result.message()));
    }
  }

  /**
   * Processes checkout for a cart.
   * <p>
   * Transaction boundary: begin_transaction → reserve all items → authorize card → commit order →
   * end_transaction → publish ship messages (async, fire-and-forget, outside transaction)
   * <p>
   * Returns 200 with order_id on success. Returns 402 if payment declined, 409 if out of stock, 404
   * if cart not found.
   */
  @PostMapping("/shopping-carts/{shoppingCartId}/checkout")
  public ResponseEntity<?> checkout(
      @PathVariable int shoppingCartId,
      @Valid @RequestBody CheckoutRequest request) {
    SimulatedLoad.busyWait(SimulatedLoad.logNormalDelayMs());
    CheckoutResult result = cartService.checkout(shoppingCartId, request.getCredit_card_number());

    if (result.status() == CheckoutResult.Status.SUCCESS) {
      return ResponseEntity.ok(Map.of("order_id", result.orderId()));
    } else if (result.status() == CheckoutResult.Status.NOT_FOUND) {
      return ResponseEntity.status(HttpStatus.NOT_FOUND)
          .body(Map.of("error", "NOT_FOUND", "message", result.message()));
    } else if (result.status() == CheckoutResult.Status.BAD_REQUEST) {
      return ResponseEntity.badRequest()
          .body(Map.of("error", "INVALID_INPUT", "message", result.message()));
    } else if (result.status() == CheckoutResult.Status.OUT_OF_STOCK) {
      return ResponseEntity.status(HttpStatus.CONFLICT)
          .body(Map.of("error", "INSUFFICIENT_STOCK", "message", result.message()));
    } else {
      return ResponseEntity.status(HttpStatus.PAYMENT_REQUIRED)
          .body(Map.of("error", "PAYMENT_DECLINED", "message", result.message()));
    }
  }
}
