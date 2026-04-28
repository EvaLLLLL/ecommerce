package com.ecommerce.productservice.model;

import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Request body for POST /product. product_id is intentionally omitted — the server assigns it.
 */
@Data
@NoArgsConstructor
public class CreateProductRequest {

  @NotBlank(message = "sku must not be empty")
  @Size(min = 1, max = 100, message = "sku must be between 1 and 100 characters")
  private String sku;

  @NotBlank(message = "manufacturer must not be empty")
  @Size(min = 1, max = 200, message = "manufacturer must be between 1 and 200 characters")
  private String manufacturer;

  @Min(value = 1, message = "category_id must be at least 1")
  private int category_id;

  @Min(value = 0, message = "weight must be non-negative")
  private int weight;

  @Min(value = 1, message = "some_other_id must be at least 1")
  private int some_other_id;
}
