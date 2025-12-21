// ===== ESP32 BILL ACCEPTOR + COIN SLOT + BLE + RELAY =====

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// BLE Service & Characteristic UUIDs
#define SERVICE_UUID        "12345678-1234-1234-1234-1234567890ab"
#define CHARACTERISTIC_UUID "abcd1234-5678-90ab-cdef-1234567890ab"

const byte billPin = 26;          // Bill acceptor pulse pin
const byte coinPin = 19;          // Coin slot pulse pin
const byte relayPin = 4;          // Relay control pin

volatile unsigned int billPulseCount = 0;
volatile unsigned int coinPulseCount = 0;
volatile bool billInProgress = false;
volatile bool coinInProgress = false;

unsigned int credit = 0;

volatile unsigned long lastBillTime = 0;
volatile unsigned long lastCoinTime = 0;

const unsigned long billDebounce = 80;
const unsigned long coinDebounce = 80;
const unsigned long billTimeout = 200;
const unsigned long coinTimeout = 100;

BLEServer* pServer = nullptr;
BLECharacteristic* pCharacteristic = nullptr;
bool deviceConnected = false;

// ===== ISR =====
void IRAM_ATTR billPulseISR() {
  unsigned long currentTime = millis();
  if (currentTime - lastBillTime > billDebounce) {
    billPulseCount++;
    billInProgress = true;
    lastBillTime = currentTime;
  }
}

void IRAM_ATTR coinPulseISR() {
  unsigned long currentTime = millis();
  if (currentTime - lastCoinTime > coinDebounce) {
    coinPulseCount++;
    coinInProgress = true;
    lastCoinTime = currentTime;
  }
}

// ===== BLE Server Callbacks =====
class MyServerCallbacks : public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("Device connected!");
  };
  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("Device disconnected!");
  }
};

// ===== BLE Characteristic Callbacks (for WRITE) =====
class MyCharacteristicCallbacks : public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* pCharacteristic) {
    String command = String(pCharacteristic->getValue().c_str());
    command.trim();
    command.toUpperCase();
    
    if (command.length() > 0) {
      Serial.println("Received command: " + command);
      
      if (command == "START") {
        digitalWrite(relayPin, HIGH);  // Turn relay ON
        Serial.println("RELAY: ON");
        
        // Send confirmation back
        if (deviceConnected) {
          pCharacteristic->setValue("RELAY:ON");
          pCharacteristic->notify();
        }
      }
      else if (command == "STOP") {
        digitalWrite(relayPin, LOW);   // Turn relay OFF
        Serial.println("RELAY: OFF");
        
        // Send confirmation back
        if (deviceConnected) {
          pCharacteristic->setValue("RELAY:OFF");
          pCharacteristic->notify();
        }
      }
    }
  }
};

void setup() {
  Serial.begin(115200);

  // Setup Pins
  pinMode(billPin, INPUT_PULLUP);
  pinMode(coinPin, INPUT_PULLUP);
  pinMode(relayPin, OUTPUT);
  digitalWrite(relayPin, LOW);  // Start with relay OFF
  
  attachInterrupt(digitalPinToInterrupt(billPin), billPulseISR, FALLING);
  attachInterrupt(digitalPinToInterrupt(coinPin), coinPulseISR, FALLING);

  // ===== BLE Setup =====
  BLEDevice::init("LUIGI"); // BLE Device name - MUST match Flutter app
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  pCharacteristic = pService->createCharacteristic(
                      CHARACTERISTIC_UUID,
                      BLECharacteristic::PROPERTY_READ   |
                      BLECharacteristic::PROPERTY_WRITE  |
                      BLECharacteristic::PROPERTY_NOTIFY
                    );
  pCharacteristic->addDescriptor(new BLE2902());
  pCharacteristic->setCallbacks(new MyCharacteristicCallbacks());

  pService->start();
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->start();

  // Print BLE MAC
  String mac = BLEDevice::getAddress().toString().c_str();
  Serial.println("ESP32 BLE MAC: " + mac);

  Serial.println("=== Bill Acceptor + Coin Slot + Relay BLE Ready ===");
}

void loop() {
  // Process COIN
  if (coinInProgress && (millis() - lastCoinTime > coinTimeout)) {
    credit += coinPulseCount;  // 1 pulse = ₱1
    String msg = "COIN:" + String(coinPulseCount);
    Serial.println(msg);

    if (deviceConnected) {
      pCharacteristic->setValue(msg.c_str());
      pCharacteristic->notify();
    }

    coinPulseCount = 0;
    coinInProgress = false;
  }

  // Process BILL
  if (billInProgress && (millis() - lastBillTime > billTimeout)) {
    int billValue = 0;
    if (billPulseCount == 2) { billValue = 20; }
    else if (billPulseCount == 5) { billValue = 50; }

    String msg;
    if (billValue > 0) {
      credit += billValue;
      msg = "BILL:" + String(billValue);
      Serial.println(msg);
    } else {
      msg = "REJECTED:" + String(billPulseCount);
      Serial.println(msg);
    }

    if (deviceConnected) {
      pCharacteristic->setValue(msg.c_str());
      pCharacteristic->notify();
    }

    billPulseCount = 0;
    billInProgress = false;
  }

  delay(10); // small delay to avoid busy loop
}
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
