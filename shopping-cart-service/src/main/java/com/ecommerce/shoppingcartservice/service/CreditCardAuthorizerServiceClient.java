package com.ecommerce.shoppingcartservice.service;

import com.ecommerce.shoppingcartservice.config.ServicesConfig;
import java.util.Map;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

@Service
public class CreditCardAuthorizerServiceClient {

  private static final Logger log = LoggerFactory.getLogger(
      CreditCardAuthorizerServiceClient.class);

  private final ServicesConfig config;
  private final RestTemplate restTemplate;

  public CreditCardAuthorizerServiceClient(ServicesConfig config, RestTemplate restTemplate) {
    this.config = config;
    this.restTemplate = restTemplate;
  }


  /**
   * Sends a charge authorization request to the Credit Card Authorizer. Returns true if authorized
   * (200), false if declined (402).
   */
  public boolean authorize(String creditCardNumber) {
    try {
      Map<String, String> body = Map.of("credit_card_number", creditCardNumber);
      ResponseEntity<Map> response = restTemplate.postForEntity(
          config.getCcaServiceUrl() + "/credit-card-authorizer/authorize",
          new HttpEntity<>(body), Map.class);
      return response.getStatusCode().is2xxSuccessful();
    } catch (HttpClientErrorException e) {
      if (e.getStatusCode() == HttpStatus.PAYMENT_REQUIRED) {
        return false; // declined — expected 10% of the time
      }
      log.error("CCA authorize failed: {}", e.getMessage());
      throw new RuntimeException("Credit Card Authorizer error", e);
    }
  }
}
