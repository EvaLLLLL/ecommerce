package com.ecommerce.warehouseservice.controller;

import com.ecommerce.common.util.SimulatedLoad;
import com.ecommerce.warehouseservice.model.ReserveRequest;
import com.ecommerce.warehouseservice.service.InventoryService;
import jakarta.validation.Valid;
import java.util.Map;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * Synchronous HTTP endpoints for the Warehouse service.
 * <p>
 * The third warehouse operation (shipment) is handled asynchronously by ShipmentConsumer via
 * RabbitMQ and has no HTTP endpoint.
 */
@RestController
@RequestMapping("/warehouse")
public class WarehouseController {

  private final InventoryService inventoryService;

  public WarehouseController(InventoryService inventoryService) {
    this.inventoryService = inventoryService;
  }

  /**
   * Returns the available quantity for a product. Initializes inventory to 100 units if this
   * product has never been queried before. Does NOT deduct inventory — used during add-to-cart to
   * check availability.
   * <p>
   * This is an eventually-consistent read: in a distributed deployment multiple instances maintain
   * separate in-memory state, so results may differ across instances. That is acceptable here per
   * the CAP trade-off (availability > consistency for checks).
   */
  @GetMapping("/inventory/{productId}")
  public ResponseEntity<Map<String, Object>> getInventory(@PathVariable int productId) {
    if (productId < 1) {
      return ResponseEntity.badRequest()
          .body(
              Map.of("error", "INVALID_INPUT", "message", "productId must be a positive integer"));
    }

    SimulatedLoad.busyWait(SimulatedLoad.logNormalDelayMs());
    int quantity = inventoryService.checkInventory(productId);
    return ResponseEntity.ok(Map.of("product_id", productId, "available_quantity", quantity));
  }

  /**
   * Attempts to synchronously reserve inventory for a product during checkout. Returns 200 if
   * successful, 409 if there is insufficient stock.
   * <p>
   * This must be strongly consistent: the CAS-based reserve in InventoryService ensures no two
   * concurrent checkouts can both succeed for the same limited stock.
   */
  @PostMapping("/reserve")
  public ResponseEntity<Map<String, Object>> reserve(@Valid @RequestBody ReserveRequest request) {
    SimulatedLoad.busyWait(SimulatedLoad.logNormalDelayMs());
    boolean reserved = inventoryService.reserve(request.getProduct_id(), request.getQuantity());

    if (!reserved) {
      return ResponseEntity.status(HttpStatus.CONFLICT)
          .body(Map.of("error", "INSUFFICIENT_STOCK", "message",
              "Insufficient stock for product " + request.getProduct_id()));
    }
    return ResponseEntity.ok(Map.of(
        "message", "Reservation successful",
        "product_id", request.getProduct_id(),
        "quantity", request.getQuantity()));
  }

  /**
   * Releases previously reserved inventory back to available stock. Called during checkout abort
   * when a credit card is declined.
   */
  @PostMapping("/unreserve")
  public ResponseEntity<Map<String, Object>> unreserve(
      @Valid @RequestBody ReserveRequest request) {
    SimulatedLoad.busyWait(SimulatedLoad.logNormalDelayMs());
    inventoryService.unreserve(request.getProduct_id(), request.getQuantity());

    return ResponseEntity.ok(Map.of(
        "message", "Inventory released",
        "product_id", request.getProduct_id(),
        "quantity", request.getQuantity()));
  }

}
