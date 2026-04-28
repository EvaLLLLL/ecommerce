package com.ecommerce.warehouseservice.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * One product-quantity pair inside a shipment order message.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class ShipmentItem {

  private int product_id;
  private int quantity;
}
