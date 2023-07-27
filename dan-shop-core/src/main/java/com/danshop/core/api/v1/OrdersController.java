package com.danshop.core.api.v1;

import lombok.extern.slf4j.Slf4j;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

import static com.danshop.core.api.v1.OrdersController.BASE_ENDPOINT_ORDERS;
import static java.util.UUID.randomUUID;

@Slf4j
@RestController
@RequestMapping(BASE_ENDPOINT_ORDERS)
public class OrdersController {
    static final String BASE_ENDPOINT_ORDERS = "/v1/orders";

    private static final Set<UUID> ORDERS = new HashSet<>();

    @GetMapping
    public Set<UUID> getAll() {
        return ORDERS;
    }

    @PostMapping
    public UUID createOrder() {
        var orderId = addOrder();

        log.info("Order [{}] created", orderId);

        return orderId;
    }

    private static UUID addOrder() {
        var orderId = randomUUID();

        ORDERS.add(orderId);

        return orderId;
    }
}
