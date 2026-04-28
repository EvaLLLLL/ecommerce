package com.ecommerce.shoppingcartservice.model;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * Request body for POST /shopping-carts/{shoppingCartId}/checkout
 */
@Data
@NoArgsConstructor
public class CheckoutRequest {

  @NotBlank(message = "credit_card_number is required")
  @Pattern(
      regexp = "^[0-9]{4}-[0-9]{4}-[0-9]{4}-[0-9]{4}$",
      message = "credit_card_number must be in format XXXX-XXXX-XXXX-XXXX"
  )
  private String credit_card_number;
}
