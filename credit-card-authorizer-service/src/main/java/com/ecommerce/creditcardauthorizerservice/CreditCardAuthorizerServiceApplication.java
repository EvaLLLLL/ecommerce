package com.ecommerce.creditcardauthorizerservice;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication(scanBasePackages = "com.ecommerce")
public class CreditCardAuthorizerServiceApplication {

  public static void main(String[] args) {
    SpringApplication.run(CreditCardAuthorizerServiceApplication.class, args);
  }

}
