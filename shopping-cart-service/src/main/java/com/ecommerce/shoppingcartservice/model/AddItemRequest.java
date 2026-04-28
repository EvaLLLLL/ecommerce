package com.ecommerce.shoppingcartservice.model;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Request body for POST /shopping-carts/addItem.
 */
@Data
@NoArgsConstructor
public class AddItemRequest {

  @Min(value = 1, message = "product_id must be at least 1")
  private int product_id;

  @Min(value = 1, message = "customer_id must be at least 1")
  private int customer_id;

  @Min(value = 1, message = "quantity must be at least 1")
  @Max(value = 10_000, message = "quantity must be at most 10000")
  private int quantity;
}
