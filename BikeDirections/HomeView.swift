//
//  HomeView.swift
//  BikeDirections
//
//  Created by Mac-aroni on 2/24/26.
//

import SwiftUI
import MapKit

struct HomeView: View {
    @StateObject private var vm = MapViewModel()
    @StateObject private var bleManager = BluetoothManager()
    
    @State private var showStatusAlert = false
    
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        ZStack(alignment: .top) {
            // MAP
            Map(coordinateRegion: $vm.region, showsUserLocation: true,
                userTrackingMode: $vm.trackingMode, annotationItems: vm.annotations) { annotation in
                MapMarker(coordinate: annotation.coordinate, tint: .red)
            }
            .ignoresSafeArea()
            .onChange(of: vm.region.center.latitude) { _ in
                if isSearchFocused {
                    isSearchFocused = false
                }
            }
            
            // SEARCH BAR & CONNECTIVITY STATUS
            VStack(spacing: 12) {
                HStack {
                    // SEARCH BAR
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Search for a place", text: $vm.searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                            .focused($isSearchFocused)
                        
                        if !vm.searchText.isEmpty {
                            Button {
                                vm.searchText = ""
                                vm.annotations = []
                                // Keep keyboard open when clearing text
                                isSearchFocused = true
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(.systemBackground))
                    .cornerRadius(32)
                    
                    // CONNECTIVITY STATUS
                    Button {
                        showStatusAlert = true
                    } label: {
                        Image(systemName: bleManager.isConnected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                                .padding(11)
                                .bold()
                                .foregroundColor(.white)
                                .background(
                                    Circle()
                                        .fill(bleManager.isConnected ? Color.green : Color.red)
                                )
                    }
                }
                
                // RESULTS LIST
                if !vm.searchText.isEmpty && !vm.results.isEmpty {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            ForEach(vm.results) { result in
                                VStack(spacing: 0) {
                                    VStack(spacing: 0) {
                                        Button {
                                            isSearchFocused = false
                                            vm.selectResult(result)
                                        } label: {
                                            HStack {
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(result.name)
                                                        .font(.headline)
                                                        .foregroundColor(.primary)
                                                    Text(result.subtitle)
                                                        .font(.subheadline)
                                                        .foregroundColor(.secondary)
                                                }
                                                
                                                Spacer()
                                                
                                                VStack(alignment: .trailing) {
                                                    Text(result.formattedDistance)
                                                        
                                                    HStack(spacing: 2) {
                                                        Image(systemName: result.isClimbing ? "arrow.up.right" : "arrow.down.right")
                                                        Text(result.formattedClimb)
                                                    }
//                                                    .font(.system(size: 12, weight: .medium))
                                                    .foregroundColor(result.isClimbing ? .orange : .blue)
                                                }
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(.primary)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 6)
                                                .background(Color(.systemGray6))
                                                .cornerRadius(8)
                                            }
                                            .padding()
                                            .background(Color(.systemBackground))
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                        
                                        if result.id != vm.results.last?.id {
                                            Divider()
                                                .padding(.leading)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.bottom, 10)
                        .background(Color(.systemBackground))
                        .cornerRadius(32)
                    }
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.75)
                    .scrollDismissesKeyboard(.immediately)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            
            VStack {
                Spacer()
                
                if let destination = vm.selectedDestination {
                    Button {
                        // TODO: Fetch route from MapKit and display
                        print("User wants to start routing to: \(destination.name)")
                    } label: {
                        HStack {
                            // TODO: Change to actual length
                            Text("5 mins")
                            Image(systemName: "circle.fill")
                                .font(.system(size: 8))
                            Image(systemName: "bicycle")
                        }
                        .font(.title3.bold())
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(32)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.spring(), value: vm.selectedDestination?.id)
                }
            }
            .ignoresSafeArea(.keyboard)
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    
                    Button {
                        vm.trackingMode = .follow
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                            .padding()
                            .background(Color(.systemBackground))
                            .clipShape(Circle())
                            .shadow(color: Color.black.opacity(0.15), radius: 5, x: 0, y: 5)
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, vm.selectedDestination != nil ? 110 : 32)
                    .animation(.spring(), value: vm.selectedDestination?.id)
                }
            }
            .ignoresSafeArea(.keyboard)
            .alert("Connectivity Status", isPresented: $showStatusAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(bleManager.statusText)
            }
        }
        .onTapGesture {
            isSearchFocused = false
        }
    }
}

#Preview {
    HomeView()
}
