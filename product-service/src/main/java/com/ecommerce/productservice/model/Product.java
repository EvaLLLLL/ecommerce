package com.ecommerce.productservice.model;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data
@NoArgsConstructor
@AllArgsConstructor
public class Product {

  private int product_id;
  private String sku;
  private String manufacturer;
  private int category_id;
  /**
   * Product weight in grams.
   */
  private int weight;
  private int some_other_id;
}
