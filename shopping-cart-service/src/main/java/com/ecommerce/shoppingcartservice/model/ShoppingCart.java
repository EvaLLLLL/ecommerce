package com.ecommerce.shoppingcartservice.model;

import java.util.ArrayList;
import java.util.List;
import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Full shopping cart record stored in the KV database.
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class ShoppingCart {

  private int cart_id;
  private int customer_id;
  private List<CartItem> items = new ArrayList<>();
}
