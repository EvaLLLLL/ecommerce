package com.ecommerce.shoppingcartservice;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

@SpringBootApplication(scanBasePackages = "com.ecommerce")
public class ShoppingCartServiceApplication {

  public static void main(String[] args) {
    SpringApplication.run(ShoppingCartServiceApplication.class, args);
  }

}
