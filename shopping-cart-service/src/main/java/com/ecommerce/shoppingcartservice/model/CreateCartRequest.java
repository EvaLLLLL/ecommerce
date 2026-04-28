package com.ecommerce.shoppingcartservice.model;

import jakarta.validation.constraints.Min;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Request body for POST /shopping-cart
 */
@Data
@NoArgsConstructor
public class CreateCartRequest {

  @Min(value = 1, message = "customer_id must be at least 1")
  private int customer_id;
}
