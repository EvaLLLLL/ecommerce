package com.ecommerce.productservice.controller;

import com.ecommerce.productservice.model.CreateProductRequest;
import com.ecommerce.productservice.service.ProductService;
import com.ecommerce.common.util.SimulatedLoad;

import jakarta.validation.Valid;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;

@RestController
public class ProductController {

  private static final org.slf4j.Logger log =
      org.slf4j.LoggerFactory.getLogger(ProductController.class);

  private final ProductService productService;

  // ATW demo: each instance decides at startup whether it is "bad".
  // BAD_INSTANCE_CHANCE controls the probability (e.g. 0.33 → ~1 in 3 instances).
  // A bad instance returns 503 for FAULT_RATE fraction of requests.
  private final double faultRate;
  private final boolean badInstance;

  public ProductController(ProductService productService,
      @Value("${product.fault.rate:0.0}") double faultRate,
      @Value("${product.bad-instance-chance:0.0}") double badInstanceChance) {
    this.productService = productService;
    this.badInstance = ThreadLocalRandom.current().nextDouble() < badInstanceChance;
    this.faultRate = badInstance ? faultRate : 0.0;
    log.info("Product Service instance started — badInstance={}, faultRate={}", badInstance,
        this.faultRate);
  }

  private boolean isFaulty() {
    return faultRate > 0.0 && ThreadLocalRandom.current().nextDouble() < faultRate;
  }

  /**
   * Creates a new product. The server assigns the product_id. Returns 201 with the assigned
   * product_id.
   */
  @PostMapping("/product")
  public ResponseEntity<Map<String, Integer>> createProduct(
      @Valid @RequestBody CreateProductRequest request) {
    if (isFaulty()) {
      return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).build();
    }
    SimulatedLoad.busyWait(SimulatedLoad.logNormalDelayMs());
    int productId = productService.createProduct(request);
    return ResponseEntity.status(HttpStatus.CREATED).body(Map.of("product_id", productId));
  }

  /**
   * Retrieves a product by ID. Returns 200 with the full product, or 404 if not found.
   */
  @GetMapping("/products/{productId}")
  public ResponseEntity<?> getProduct(@PathVariable int productId) {
    if (isFaulty()) {
      return ResponseEntity.status(HttpStatus.SERVICE_UNAVAILABLE).build();
    }
    if (productId < 1) {
      return ResponseEntity.badRequest()
          .body(
              Map.of("error", "INVALID_INPUT", "message", "productId must be a positive integer"));
    }
    SimulatedLoad.busyWait(SimulatedLoad.logNormalDelayMs());
    return productService.getProduct(productId).<ResponseEntity<?>>map(ResponseEntity::ok).orElse(
        ResponseEntity.status(HttpStatus.NOT_FOUND)
            .body(Map.of("error", "NOT_FOUND", "message", "Product not found: " + productId)));
  }
}
