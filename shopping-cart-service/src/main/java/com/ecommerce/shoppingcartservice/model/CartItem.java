package com.ecommerce.shoppingcartservice.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * A single line item inside a shopping cart.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class CartItem {

  private int product_id;
  private int quantity;
  /**
   * Total weight of this line item in grams: product.weight × quantity.
   */
  private int weight;
}
