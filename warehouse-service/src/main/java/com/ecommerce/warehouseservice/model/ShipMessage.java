package com.ecommerce.warehouseservice.model;

import java.util.ArrayList;
import java.util.List;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Message payload published to the RabbitMQ ship queue by the Shopping Cart Service after a
 * successful checkout. Consumed asynchronously by the Warehouse.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class ShipMessage {

  private int order_id;
  private List<ShipmentItem> items = new ArrayList<>();
}
