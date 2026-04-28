package com.ecommerce.warehouseservice.model;

import jakarta.validation.constraints.Min;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Request body for POST /warehouse/reserve
 */
@Data
@NoArgsConstructor
public class ReserveRequest {

  @Min(value = 1, message = "product_id must be at least 1")
  private int product_id;

  @Min(value = 1, message = "quantity must be at least 1")
  private int quantity;
}
