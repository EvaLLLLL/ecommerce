package com.ecommerce.kvdatabase.model;

import jakarta.validation.constraints.NotBlank;

public record TransactionRequest(
    @NotBlank String transaction_id
) {

}
