package com.ecommerce.kvdatabase.model;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public record KvRequest(@NotBlank String key, @NotNull String value, Integer version) {

}
