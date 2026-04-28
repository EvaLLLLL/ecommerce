package com.ecommerce.dataloader;

import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;

/**
 * Generates random product data matching the Product Service's CreateProductRequest schema.
 */
public class ProductGenerator {

  private static final String SKU_CHARS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
  private static final int SKU_LENGTH = 10;

  /**
   * Generates a random product as a Map (snake_case keys matching the API schema). Does not include
   * product_id — the server assigns it.
   */
  public Map<String, Object> generate() {
    ThreadLocalRandom r = ThreadLocalRandom.current();
    return Map.of(
        "sku", randomSku(),
        "manufacturer", "Manufacturer-" + r.nextInt(1, 1001),
        "category_id", r.nextInt(1, 100_001),
        "weight", r.nextInt(100, 10_001),
        "some_other_id", r.nextInt(1, Integer.MAX_VALUE)
    );
  }

  private String randomSku() {
    ThreadLocalRandom r = ThreadLocalRandom.current();
    StringBuilder sb = new StringBuilder(SKU_LENGTH);
    for (int i = 0; i < SKU_LENGTH; i++) {
      sb.append(SKU_CHARS.charAt(r.nextInt(SKU_CHARS.length())));
    }
    return sb.toString();
  }
}
