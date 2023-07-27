package com.danshop.core.api.v1;

import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;

import java.util.UUID;

import static com.danshop.core.api.v1.OrdersController.BASE_ENDPOINT_ORDERS;
import static org.apache.logging.log4j.util.Strings.EMPTY;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.springframework.boot.test.context.SpringBootTest.WebEnvironment.RANDOM_PORT;
import static org.springframework.http.HttpStatus.OK;

@SpringBootTest(webEnvironment = RANDOM_PORT)
class OrdersControllerTest {

    @Autowired
    private TestRestTemplate testRestTemplate;

    @Test
    void shouldCreateOrder() {
        ResponseEntity<UUID> response = testRestTemplate
                .postForEntity(BASE_ENDPOINT_ORDERS, new HttpEntity<>(EMPTY, new HttpHeaders()), UUID.class);

        assertNotNull(response.getBody());
        assertEquals(OK, response.getStatusCode());
    }

    @Test
    void shouldGetOrders() {
        testRestTemplate.postForEntity(BASE_ENDPOINT_ORDERS, new HttpEntity<>(EMPTY, new HttpHeaders()), UUID.class);
        testRestTemplate.postForEntity(BASE_ENDPOINT_ORDERS, new HttpEntity<>(EMPTY, new HttpHeaders()), UUID.class);

        ResponseEntity<UUID[]> response = testRestTemplate
                .getForEntity(BASE_ENDPOINT_ORDERS, UUID[].class);

        UUID[] responseBody = response.getBody();
        assertNotNull(responseBody);
        assertEquals(OK, response.getStatusCode());
        assertEquals(2, responseBody.length);
    }

}
