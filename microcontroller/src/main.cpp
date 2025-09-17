#include <stdio.h>
#include <inttypes.h>
#include <string.h>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "freertos/event_groups.h"
#include "driver/gpio.h"
#include "esp_system.h"
#include "esp_wifi.h"
#include "esp_event.h"
#include "esp_log.h"
#include "esp_http_client.h"
#include "esp_tls.h"
#include "esp_sntp.h"
#include "nvs_flash.h"
#include "dht.h"
#include "esp_adc/adc_oneshot.h"
#include "esp_adc/adc_cali.h"
#include "adc_cali_schemes.h"
#include "config.h"

#define LED_BLUE_PIN GPIO_NUM_5   // Frío
#define LED_GREEN_PIN GPIO_NUM_6  // Normal
#define LED_RED_PIN GPIO_NUM_7    // Caliente
#define DHT_PIN GPIO_NUM_3
#define LDR_PIN ADC_CHANNEL_4

#define WIFI_SSID "Pandora"
#define WIFI_PASS "Leopardo#1" 
#define SERVER_URL "http://" SERVER_HOST "/metric"
#define SOURCE "ESP32"
#define DEFAULT_VREF 1100

#define WIFI_CONNECTED_BIT BIT0
#define WIFI_FAIL_BIT      BIT1

static const char *TAG = "SENSOR_WIFI";
static EventGroupHandle_t s_wifi_event_group;
static adc_oneshot_unit_handle_t adc1_handle;

static void event_handler(void* arg, esp_event_base_t event_base,
                         int32_t event_id, void* event_data)
{
    if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_START) {
        esp_wifi_connect();
    } else if (event_base == WIFI_EVENT && event_id == WIFI_EVENT_STA_DISCONNECTED) {
        esp_wifi_connect();
        xEventGroupClearBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
        ESP_LOGI(TAG, "Retrying to connect to WiFi...");
    } else if (event_base == IP_EVENT && event_id == IP_EVENT_STA_GOT_IP) {
        ip_event_got_ip_t* event = (ip_event_got_ip_t*) event_data;
        ESP_LOGI(TAG, "IP obtained:" IPSTR, IP2STR(&event->ip_info.ip));
        xEventGroupSetBits(s_wifi_event_group, WIFI_CONNECTED_BIT);
    }
}

esp_err_t wifi_init_sta(void)
{
    s_wifi_event_group = xEventGroupCreate();

    ESP_ERROR_CHECK(esp_netif_init());
    ESP_ERROR_CHECK(esp_event_loop_create_default());
    esp_netif_create_default_wifi_sta();

    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    ESP_ERROR_CHECK(esp_wifi_init(&cfg));

    esp_event_handler_instance_t instance_any_id;
    esp_event_handler_instance_t instance_got_ip;
    ESP_ERROR_CHECK(esp_event_handler_instance_register(WIFI_EVENT,
                                                        ESP_EVENT_ANY_ID,
                                                        &event_handler,
                                                        NULL,
                                                        &instance_any_id));
    ESP_ERROR_CHECK(esp_event_handler_instance_register(IP_EVENT,
                                                        IP_EVENT_STA_GOT_IP,
                                                        &event_handler,
                                                        NULL,
                                                        &instance_got_ip));

    wifi_config_t wifi_config = {};
    strcpy((char*)wifi_config.sta.ssid, WIFI_SSID);
    strcpy((char*)wifi_config.sta.password, WIFI_PASS);
    wifi_config.sta.threshold.authmode = WIFI_AUTH_WPA2_PSK;
    wifi_config.sta.pmf_cfg.capable = true;
    wifi_config.sta.pmf_cfg.required = false;
    ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_STA) );
    ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_STA, &wifi_config) );
    ESP_ERROR_CHECK(esp_wifi_start() );

    ESP_LOGI(TAG, "WiFi initialization completed.");

    EventBits_t bits = xEventGroupWaitBits(s_wifi_event_group,
            WIFI_CONNECTED_BIT | WIFI_FAIL_BIT,
            pdFALSE,
            pdFALSE,
            portMAX_DELAY);

    if (bits & WIFI_CONNECTED_BIT) {
        ESP_LOGI(TAG, "Connected to WiFi SSID:%s", WIFI_SSID);
        return ESP_OK;
    } else if (bits & WIFI_FAIL_BIT) {
        ESP_LOGI(TAG, "Failed to connect to WiFi SSID:%s", WIFI_SSID);
        return ESP_FAIL;
    } else {
        ESP_LOGE(TAG, "Unexpected event");
        return ESP_FAIL;
    }
}

void initialize_sntp(void)
{
    ESP_LOGI(TAG, "Initializing SNTP");
    esp_sntp_setoperatingmode(SNTP_OPMODE_POLL);
    esp_sntp_setservername(0, "pool.ntp.org");
    esp_sntp_setservername(1, "time.nist.gov");
    esp_sntp_init();
    
    // Wait for time to be set
    time_t now = 0;
    struct tm timeinfo = { 0 };
    int retry = 0;
    const int retry_count = 10;
    
    while (sntp_get_sync_status() == SNTP_SYNC_STATUS_RESET && ++retry < retry_count) {
        ESP_LOGI(TAG, "Waiting for system time to be set... (%d/%d)", retry, retry_count);
        vTaskDelay(2000 / portTICK_PERIOD_MS);
    }
    
    time(&now);
    localtime_r(&now, &timeinfo);
    ESP_LOGI(TAG, "Time synchronized: %s", asctime(&timeinfo));
}

esp_err_t send_metric(const char* sensor_type, float value)
{
    char post_data[200];
    snprintf(post_data, sizeof(post_data), 
             "{\"source\":\"%s\",\"sensor\":\"%s\",\"value\":%.1f}", SOURCE, sensor_type, value);

    esp_http_client_config_t config = {};
    config.url = SERVER_URL;
    config.method = HTTP_METHOD_POST;
    config.timeout_ms = 10000;
    
    esp_http_client_handle_t client = esp_http_client_init(&config);
    
    esp_http_client_set_header(client, "Content-Type", "application/json");
    esp_http_client_set_header(client, "protected", AUTH_TOKEN);
    esp_http_client_set_post_field(client, post_data, strlen(post_data));
    
    esp_err_t err = esp_http_client_perform(client);
    if (err == ESP_OK) {
        ESP_LOGI(TAG, "Metric sent - Status = %d", esp_http_client_get_status_code(client));
    } else {
        ESP_LOGE(TAG, "Error sending metric: %s", esp_err_to_name(err));
    }
    
    esp_http_client_cleanup(client);
    return err;
}

int read_ldr_value(void)
{
    int adc_reading = 0;
    int raw;
    for (int i = 0; i < 64; i++) {
        ESP_ERROR_CHECK(adc_oneshot_read(adc1_handle, ADC_CHANNEL_4, &raw));
        adc_reading += raw;
    }
    adc_reading /= 64;
    return adc_reading;
}

void control_temperature_leds(float temperature)
{
    // Apagar todos los LEDs primero
    gpio_set_level(LED_BLUE_PIN, 0);
    gpio_set_level(LED_GREEN_PIN, 0);
    gpio_set_level(LED_RED_PIN, 0);
    
    if (temperature <= 20.0) {
        // Temperatura fría - LED azul
        gpio_set_level(LED_BLUE_PIN, 1);
        ESP_LOGI(TAG, "Temperature: %.1f°C - COLD (Blue LED)", temperature);
    } else if (temperature <= 28.0) {
        // Temperatura normal - LED verde (20.1°C - 28.0°C)
        gpio_set_level(LED_GREEN_PIN, 1);
        ESP_LOGI(TAG, "Temperature: %.1f°C - NORMAL (Green LED)", temperature);
    } else {
        // Temperatura caliente - LED rojo (> 28.0°C)
        gpio_set_level(LED_RED_PIN, 1);
        ESP_LOGI(TAG, "Temperature: %.1f°C - HOT (Red LED)", temperature);
    }
}

extern "C" void app_main() {
    ESP_ERROR_CHECK(nvs_flash_init());
    
    gpio_reset_pin(LED_BLUE_PIN);
    gpio_set_direction(LED_BLUE_PIN, GPIO_MODE_OUTPUT);
    gpio_reset_pin(LED_GREEN_PIN);
    gpio_set_direction(LED_GREEN_PIN, GPIO_MODE_OUTPUT);
    gpio_reset_pin(LED_RED_PIN);
    gpio_set_direction(LED_RED_PIN, GPIO_MODE_OUTPUT);
    
    // Configure ADC oneshot
    adc_oneshot_unit_init_cfg_t init_config1 = {
        .unit_id = ADC_UNIT_1,
        .clk_src = ADC_DIGI_CLK_SRC_DEFAULT,
        .ulp_mode = ADC_ULP_MODE_DISABLE,
    };
    ESP_ERROR_CHECK(adc_oneshot_new_unit(&init_config1, &adc1_handle));

    adc_oneshot_chan_cfg_t config = {
        .atten = ADC_ATTEN_DB_12,
        .bitwidth = ADC_BITWIDTH_DEFAULT,
    };
    ESP_ERROR_CHECK(adc_oneshot_config_channel(adc1_handle, ADC_CHANNEL_4, &config));
    
    ESP_LOGI(TAG, "Starting WiFi connection...");
    wifi_init_sta();
    
    vTaskDelay(2000 / portTICK_PERIOD_MS);
    
    // Initialize time sync for HTTPS certificate validation
    initialize_sntp();
    
    vTaskDelay(3000 / portTICK_PERIOD_MS);
    
    while(1) {
        printf("Trying to read DHT22...\n");
        
        // Leer temperatura y humedad del sensor DHT22
        int16_t temperature = 0;
        int16_t humidity = 0;
        
        esp_err_t res = dht_read_data(DHT_TYPE_AM2301, DHT_PIN, &humidity, &temperature);
        
        if (res == ESP_OK) {
            float temp = temperature / 10.0;
            float hum = humidity / 10.0;
            printf("Successful reading - Temperature: %.1f°C, Humidity: %.1f%%\n", temp, hum);
            
            // Controlar LEDs basado en temperatura
            control_temperature_leds(temp);
            
            EventBits_t bits = xEventGroupGetBits(s_wifi_event_group);
            if (bits & WIFI_CONNECTED_BIT) {
                ESP_LOGI(TAG, "Sending temperature metric to server...");
                send_metric("temperature", temp);
                vTaskDelay(100 / portTICK_PERIOD_MS);
                
                ESP_LOGI(TAG, "Sending humidity metric to server...");
                send_metric("humidity", hum);
                vTaskDelay(100 / portTICK_PERIOD_MS);
                
                int ldr_value = read_ldr_value();
                float ldr_percentage = (ldr_value / 4095.0) * 100.0;
                ESP_LOGI(TAG, "LDR reading: %d (%.1f%%)", ldr_value, ldr_percentage);
                ESP_LOGI(TAG, "Sending light metric to server...");
                send_metric("light", ldr_percentage);
            } else {
                ESP_LOGW(TAG, "WiFi not connected, cannot send data");
            }
        } else {
            printf("Error reading DHT22: %s (code: %d)\n", esp_err_to_name(res), res);
            // En caso de error, apagar todos los LEDs
            gpio_set_level(LED_BLUE_PIN, 0);
            gpio_set_level(LED_GREEN_PIN, 0);
            gpio_set_level(LED_RED_PIN, 0);
        }
        
        vTaskDelay(5000 / portTICK_PERIOD_MS);  // Esperar 5 segundos entre lecturas
    }
}