#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// These MUST match the UUIDs exactly from your Swift code!
#define SERVICE_UUID        "4FAFc201-1FB5-459E-8FCC-C5C9C331914B"
#define CHARACTERISTIC_UUID "BEB5483E-36E1-4688-B7F5-EA07361B26A8"

// Define the pins where your motors (or test LEDs) will be connected
const int leftMotorPin = 25;  
const int rightMotorPin = 26; 

bool deviceConnected = false;
bool oldDeviceConnected = false;

// 1. Callback class to handle device connection/disconnection
class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("🟢 iPhone Connected!");
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("🔴 iPhone Disconnected!");
    }
};

// 2. Callback class to handle incoming data from the iPhone
class MyCallbacks: public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
      // 👇 FIX 1: We use the Arduino 'String' type now
      String rxValue = pCharacteristic->getValue();

      if (rxValue.length() > 0) {
        // 👇 FIX 2: safely grab the first byte of the payload
        uint8_t command = (uint8_t)rxValue[0]; 
        
        if (command == 1) {
          Serial.println("⬅️ Received Left Command");
          digitalWrite(leftMotorPin, HIGH);
          delay(500); 
          digitalWrite(leftMotorPin, LOW);
          
        } else if (command == 2) {
          Serial.println("➡️ Received Right Command");
          digitalWrite(rightMotorPin, HIGH);
          delay(500); 
          digitalWrite(rightMotorPin, LOW);
        }
      }
    }
};

void setup() {
  Serial.begin(115200);
  
  // Set the motor pins as outputs and ensure they are OFF by default
  pinMode(leftMotorPin, OUTPUT);
  pinMode(rightMotorPin, OUTPUT);
  digitalWrite(leftMotorPin, LOW);
  digitalWrite(rightMotorPin, LOW);

  Serial.println("Starting BLE Server...");

  // Initialize the BLE device with a name (this is what shows up in scanners)
  BLEDevice::init("Bike_Nav_ESP32");

  // Create the BLE Server
  BLEServer *pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  // Create the BLE Service
  BLEService *pService = pServer->createService(SERVICE_UUID);

  // Create the BLE Characteristic for writing data
  BLECharacteristic *pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_WRITE
  );

  pCharacteristic->setCallbacks(new MyCallbacks());

  // Start the service
  pService->start();

  // Start advertising the Service UUID so the iPhone can find it
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  
  // These settings help iOS discover the device faster
  pAdvertising->setMinPreferred(0x06);  
  pAdvertising->setMinPreferred(0x12);
  
  BLEDevice::startAdvertising();
  Serial.println("📡 Advertising started. Waiting for iOS App to connect...");
}

void loop() {
  // If the device just disconnected
  if (!deviceConnected && oldDeviceConnected) {
      delay(500); // Give the Bluetooth stack time to fully sever the connection
      BLEDevice::startAdvertising(); // Safely restart advertising
      Serial.println("📡 Restarted Advertising. Waiting to reconnect...");
      oldDeviceConnected = deviceConnected;
  }

  // If the device just connected
  if (deviceConnected && !oldDeviceConnected) {
      // Do nothing, just update the state tracker
      oldDeviceConnected = deviceConnected;
  }
  
  delay(10); // Small delay to keep the loop running smoothly
}