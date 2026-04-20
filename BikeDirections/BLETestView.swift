//
//  BLETestView.swift
//  BikeDirections
//
//  Created by Mac-aroni on 2/24/26.
//

import SwiftUI

struct BLETestView: View {
    @StateObject private var bleManager = BluetoothManager()

    var body: some View {
        VStack(spacing: 40) {
            Text(bleManager.statusText)
                .font(.headline)

            HStack(spacing: 30) {
                // LEFT BUTTON
                Button {
                    bleManager.sendCommand(1)
                } label: {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 100, height: 100)
                        .background(bleManager.isConnected ? Color.blue : Color.gray)
                        .cornerRadius(20)
                }
                .disabled(!bleManager.isConnected)

                // RIGHT BUTTON
                Button {
                    bleManager.sendCommand(2)
                } label: {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 100, height: 100)
                        .background(bleManager.isConnected ? Color.blue : Color.gray)
                        .cornerRadius(20)
                }
                .disabled(!bleManager.isConnected)
            }
        }
    }
}

#Preview {
    BLETestView()
}
