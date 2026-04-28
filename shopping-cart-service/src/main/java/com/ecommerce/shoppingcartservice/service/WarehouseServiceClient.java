package com.ecommerce.shoppingcartservice.service;

import com.ecommerce.shoppingcartservice.config.ServicesConfig;
import com.ecommerce.shoppingcartservice.model.CartItem;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

@Service
public class WarehouseServiceClient {

  private static final Logger log = LoggerFactory.getLogger(WarehouseServiceClient.class);

  private final ServicesConfig config;
  private final RestTemplate restTemplate;

  public WarehouseServiceClient(ServicesConfig config, RestTemplate restTemplate) {
    this.config = config;
    this.restTemplate = restTemplate;
  }

  /**
   * Checks available inventory quantity from the Warehouse Service. Returns 0 if the product is
   * unknown (Warehouse will initialize it to 100).
   */
  public int checkInventory(int productId) {
    try {
      ResponseEntity<Map> response = restTemplate.getForEntity(
          config.getWarehouseServiceUrl() + "/warehouse/inventory/" + productId, Map.class);
      if (response.getStatusCode().is2xxSuccessful() && response.getBody() != null) {
        Object qty = response.getBody().get("available_quantity");
        return qty != null ? ((Number) qty).intValue() : 0;
      }
      return 0;
    } catch (Exception e) {
      log.error("Inventory check failed for product {}: {}", productId, e.getMessage());
      throw new RuntimeException("Warehouse Service unavailable", e);
    }
  }

  /**
   * Attempts to reserve inventory for a single cart item. Returns true if reservation succeeded,
   * false if insufficient stock.
   */
  public boolean reserve(int productId, int quantity) {
    try {
      Map<String, Integer> body = Map.of("product_id", productId, "quantity", quantity);
      ResponseEntity<Map> response = restTemplate.postForEntity(
          config.getWarehouseServiceUrl() + "/warehouse/reserve",
          new HttpEntity<>(body), Map.class);
      return response.getStatusCode().is2xxSuccessful();
    } catch (HttpClientErrorException e) {
      if (e.getStatusCode() == HttpStatus.CONFLICT) {
        return false; // insufficient stock
      }
      log.error("Reserve failed for product {}: {}", productId, e.getMessage());
      throw new RuntimeException("Warehouse Service error during reservation", e);
    }
  }

  /**
   * Releases a previously reserved quantity back to the Warehouse. Called when checkout is aborted
   * after reservation but before ship.
   */
  public void unreserve(int productId, int quantity) {
    try {
      Map<String, Integer> body = Map.of("product_id", productId, "quantity", quantity);
      restTemplate.postForEntity(
          config.getWarehouseServiceUrl() + "/warehouse/unreserve",
          new HttpEntity<>(body), Map.class);
    } catch (Exception e) {
      // Best-effort: log and continue — reservation leak is acceptable in this simulation
      log.error("Unreserve failed for product {} qty {}: {}", productId, quantity, e.getMessage());
    }
  }

  /**
   * Unreserves all items in a list — used when rolling back after a failed step.
   */
  public void unreserveAll(java.util.List<CartItem> reservedItems) {
    for (CartItem item : reservedItems) {
      unreserve(item.getProduct_id(), item.getQuantity());
    }
  }
}
