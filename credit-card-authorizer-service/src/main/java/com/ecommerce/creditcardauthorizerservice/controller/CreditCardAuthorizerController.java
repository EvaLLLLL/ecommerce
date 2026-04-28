package com.ecommerce.creditcardauthorizerservice.controller;

import com.ecommerce.creditcardauthorizerservice.model.AuthorizeRequest;
import com.ecommerce.common.util.SimulatedLoad;
import jakarta.validation.Valid;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/credit-card-authorizer")
public class CreditCardAuthorizerController {

  private static final double DECLINE_RATE = 0.10;

  @PostMapping("/authorize")
  public ResponseEntity<Map<String, String>> authorize(
      @Valid @RequestBody AuthorizeRequest request) {
    SimulatedLoad.busyWait(SimulatedLoad.logNormalDelayMs());

    if (ThreadLocalRandom.current().nextDouble() < DECLINE_RATE) {
      return ResponseEntity.status(HttpStatus.PAYMENT_REQUIRED)
          .body(Map.of("error", "PAYMENT_DECLINED", "message", "Payment declined"));
    }
    return ResponseEntity.ok(Map.of("message", "Payment authorized"));
  }
}
