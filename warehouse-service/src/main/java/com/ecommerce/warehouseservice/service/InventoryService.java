package com.ecommerce.warehouseservice.service;

import jakarta.annotation.PreDestroy;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.Set;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import com.ecommerce.warehouseservice.model.ShipmentItem;
import org.springframework.stereotype.Service;

/**
 * In-memory inventory tracker for the Warehouse service.
 * <p>
 * Each product starts with 100 units the first time it is queried. All operations are thread-safe:
 * inventory uses AtomicInteger per product, and the reserve operation uses a CAS loop to atomically
 * check-and-deduct without locks or races.
 * <p>
 * Note: inventory is lost on restart (by design — no persistent storage).
 */
@Service
public class InventoryService {

  private static final Logger log = LoggerFactory.getLogger(InventoryService.class);
  private static final int INITIAL_QUANTITY = 100;

  /**
   * Maps productId → available quantity. Initialized lazily on first access.
   */
  private final ConcurrentHashMap<Integer, AtomicInteger> inventory = new ConcurrentHashMap<>();

  /**
   * Maps productId → total quantity successfully shipped.
   */
  private final ConcurrentHashMap<Integer, AtomicInteger> shippedQuantityByProduct =
      new ConcurrentHashMap<>();

  /**
   * Total number of ship orders successfully processed from the RabbitMQ queue.
   */
  private final AtomicInteger totalOrdersProcessed = new AtomicInteger(0);

  /**
   * Used to keep shipment accounting idempotent if RabbitMQ redelivers a message.
   */
  private final Set<Integer> processedOrderIds = ConcurrentHashMap.newKeySet();

  /**
   * Returns the current available quantity for the given product. If the product has never been
   * queried before, it is initialized with 100 units. Does NOT deduct inventory — safe for use
   * during add-to-cart checks.
   */
  public int checkInventory(int productId) {
    return getOrInitStock(productId).get();
  }

  /**
   * Attempts to reserve the requested quantity for a product. Uses a CAS loop so the
   * check-and-deduct is atomic even under concurrent requests.
   *
   * @return true if reservation succeeded, false if there is insufficient stock
   */
  public boolean reserve(int productId, int quantity) {
    AtomicInteger stock = getOrInitStock(productId);
    while (true) {
      int current = stock.get();
      if (current < quantity) {
        return false;
      }
      // Atomically swap only if the value hasn't changed since we read it
      if (stock.compareAndSet(current, current - quantity)) {
        log.debug("Reserved {} units of product {}; remaining: {}", quantity, productId,
            current - quantity);
        return true;
      }
      // Another thread changed the value — retry
    }
  }

  /**
   * Releases a previously reserved quantity back to available stock. Called when a checkout is
   * aborted (e.g. credit card declined).
   */
  public void unreserve(int productId, int quantity) {
    getOrInitStock(productId).addAndGet(quantity);
    log.debug("Unreserved {} units of product {}", quantity, productId);
  }

  /**
   * Records a completed shipment after checkout.
   * <p>
   * Inventory was already deducted during reserve(), so shipping must not decrease stock again.
   * Instead, the Warehouse keeps the required Assignment 3 aggregates: 1. total number of orders 2.
   * total quantity ordered per product ID
   */
  public void shipOrder(int orderId, java.util.List<ShipmentItem> items) {
    if (!processedOrderIds.add(orderId)) {
      log.warn("Ignoring duplicate shipment message for order {}", orderId);
      return;
    }

    for (ShipmentItem item : items) {
      shippedQuantityByProduct
          .computeIfAbsent(item.getProduct_id(), ignored -> new AtomicInteger(0))
          .addAndGet(item.getQuantity());
      log.debug("Recorded shipment for order {} product {} qty {}", orderId,
          item.getProduct_id(), item.getQuantity());
    }

    totalOrdersProcessed.incrementAndGet();
  }

  public int getTotalOrdersProcessed() {
    return totalOrdersProcessed.get();
  }

  /**
   * Prints a summary when the service shuts down, as required by Assignment 3.
   */
  @PreDestroy
  public void printShutdownStats() {
    log.info("=== Warehouse shutdown: total orders processed = {} ===",
        totalOrdersProcessed.get());
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  private AtomicInteger getOrInitStock(int productId) {
    return inventory.computeIfAbsent(productId, k -> new AtomicInteger(INITIAL_QUANTITY));
  }
}
