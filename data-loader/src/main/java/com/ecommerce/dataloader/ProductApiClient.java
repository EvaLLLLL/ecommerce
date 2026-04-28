package com.ecommerce.dataloader;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.Map;
import tools.jackson.databind.ObjectMapper;

/**
 * Lightweight HTTP client for posting products to the Product Service.
 */
public class ProductApiClient {

  private static final ObjectMapper MAPPER = new ObjectMapper();

  private final String baseUrl;
  private final HttpClient httpClient;

  public ProductApiClient(String baseUrl) {
    this.baseUrl = baseUrl;
    this.httpClient = HttpClient.newHttpClient();
  }

  /**
   * Posts a product to POST /product. Returns the assigned product_id, or -1 on failure.
   */
  public int createProduct(Map<String, Object> productData) {
    try {
      String json = MAPPER.writeValueAsString(productData);
      HttpRequest request = HttpRequest.newBuilder()
          .uri(URI.create(baseUrl + "/product"))
          .header("Content-Type", "application/json")
          .POST(HttpRequest.BodyPublishers.ofString(json))
          .build();

      HttpResponse<String> response = httpClient.send(request,
          HttpResponse.BodyHandlers.ofString());

      if (response.statusCode() == 201) {
        @SuppressWarnings("unchecked")
        Map<String, Object> body = MAPPER.readValue(response.body(), Map.class);
        return ((Number) body.get("product_id")).intValue();
      } else {
        System.err.println(
            "POST /product failed: " + response.statusCode() + " " + response.body());
        return -1;
      }
    } catch (Exception e) {
      System.err.println("POST /product error: " + e.getMessage());
      return -1;
    }
  }
}
