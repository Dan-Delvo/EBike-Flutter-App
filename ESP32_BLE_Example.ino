/*
 * ESP32 BLE Server Example for E-Bike Charging Station
 * 
 * IMPORTANT: This uses BLE (Bluetooth Low Energy), NOT Classic Bluetooth
 * ESP32 with WiFi 802.11 b/g/n + Bluetooth
 * 
 * This code:
 * - Disables WiFi to prevent radio interference
 * - Uses BLE for communication with Flutter app
 * - Prints BLE MAC address on startup
 */

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include <WiFi.h>

// Device name - MUST match the name in your Flutter app
#define DEVICE_NAME "LUIGI"

// UUIDs for the service and characteristics
// You can generate your own UUIDs at https://www.uuidgenerator.net/
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;
bool oldDeviceConnected = false;

// Callback class for server connection events
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("Device connected!");
    }

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("Device disconnected!");
    }
};

// Callback class for characteristic events (receiving data from Flutter)
class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      String value = pCharacteristic->getValue();
      
      if (value.length() > 0) {
        Serial.print("Received from Flutter: ");
        Serial.println(value);
        
        // Handle commands from Flutter app
        if (value == "COIN") {
          Serial.println("Coin test requested");
          // You can trigger coin acceptor logic here
        }
        else if (value == "BILL") {
          Serial.println("Bill test requested");
          // You can trigger bill acceptor logic here
        }
      }
    }
};

void setup() {
  Serial.begin(115200);
  Serial.println("Starting BLE Server...");
  Serial.println("ESP32 with WiFi + Bluetooth detected");

  // IMPORTANT: Disable WiFi to avoid radio interference with BLE
  // ESP32 WiFi and Bluetooth share the same radio
  WiFi.mode(WIFI_OFF);
  btStop(); // Stop classic bluetooth if running
  
  delay(100);

  // Create the BLE Device
  BLEDevice::init(DEVICE_NAME);
  
  // Get and print the BLE MAC address
  Serial.print("BLE MAC Address: ");
  Serial.println(BLEDevice::getAddress().toString().c_str());

  // Create the BLE Server
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // Create the BLE Service
  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Create a BLE Characteristic
  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ   |
                      BLECharacteristic::PROPERTY_WRITE  |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );

  // Create a BLE Descriptor for notifications
  pCharacteristic->addDescriptor(new BLE2902());
  pCharacteristic->setCallbacks(new MyCallbacks());

  // Start the service
  pService->start();

  // Start advertising
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pAdvertising->setMinPreferred(0x06);  // helps with iPhone connections
  pAdvertising->setMinPreferred(0x12);
  BLEDevice::startAdvertising();
  
  Serial.println("BLE Server is now advertising!");
  Serial.print("Device name: ");
  Serial.println(DEVICE_NAME);
  Serial.println("Waiting for Flutter app to connect...");
}

void loop() {
  // When device disconnects, restart advertising
  if (!deviceConnected && oldDeviceConnected) {
    delay(500); // give the bluetooth stack time to get ready
    pServer->startAdvertising();
    Serial.println("Restarting advertising...");
    oldDeviceConnected = deviceConnected;
  }
  
  // When device connects
  if (deviceConnected && !oldDeviceConnected) {
    oldDeviceConnected = deviceConnected;
  }

  // Example: Send coin notification every 10 seconds (for testing)
  static unsigned long lastSend = 0;
  if (deviceConnected && millis() - lastSend > 10000) {
    // Send a test message to Flutter
    String message = "COIN:5";
    pCharacteristic->setValue(message.c_str());
    pCharacteristic->notify();
    Serial.print("Sent to Flutter: ");
    Serial.println(message);
    lastSend = millis();
  }

  delay(100);
}

/* 
 * COIN ACCEPTOR INTEGRATION EXAMPLE:
 * 
 * Connect your coin acceptor to a GPIO pin (e.g., GPIO 4)
 * When a coin is detected, send the amount:
 * 
 * const int COIN_PIN = 4;
 * 
 * void setup() {
 *   pinMode(COIN_PIN, INPUT_PULLUP);
 * }
 * 
 * void loop() {
 *   if (digitalRead(COIN_PIN) == LOW && deviceConnected) {
 *     String message = "COIN:5"; // 5 pesos
 *     pCharacteristic->setValue(message.c_str());
 *     pCharacteristic->notify();
 *     delay(500); // debounce
 *   }
 * }
 */
