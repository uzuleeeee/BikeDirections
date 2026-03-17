import SwiftUI
import MapKit

struct HomeView: View {
    @StateObject private var vm = MapViewModel()
    @StateObject private var bleManager = BluetoothManager()

    @State private var showStatusAlert = false

    @FocusState private var isSearchFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            NavigationMapView(viewModel: vm)
                .ignoresSafeArea()
                .onAppear {
                    vm.attachBluetoothManager(bleManager)
                }

            VStack(spacing: 12) {
                HStack {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)

                        TextField("Search for a place", text: $vm.searchText)
                            .textFieldStyle(.plain)
                            .focused($isSearchFocused)

                        if !vm.searchText.isEmpty {
                            Button {
                                vm.searchText = ""
                                vm.annotations = []
                                vm.stopNavigation(resetDestination: true)
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

                if vm.isNavigating {
                    navigationBanner
                }

                if !vm.searchText.isEmpty && !vm.results.isEmpty {
                    resultsList
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            VStack {
                Spacer()

                if vm.isNavigating {
                    activeRouteControls
                } else if let destination = vm.selectedDestination {
                    startRouteButton(destination: destination)
                }
            }
            .ignoresSafeArea(.keyboard)

            VStack {
                Spacer()

                HStack {
                    Spacer()

                    Button {
                        vm.recenterOnUser()
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
                    .padding(.bottom, vm.isNavigating || vm.selectedDestination != nil ? 150 : 32)
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

    private var navigationBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current instruction")
                .font(.caption)
                .foregroundColor(.secondary)

            Text(vm.currentInstruction)
                .font(.headline)
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let details = vm.routeDetails {
                HStack(spacing: 10) {
                    Label(details.formattedDistance, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                    Label(details.formattedTravelTime, systemImage: "clock")
                }
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }

    private var resultsList: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(vm.results) { result in
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
                        .buttonStyle(.plain)

                        if result.id != vm.results.last?.id {
                            Divider()
                                .padding(.leading)
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

    private func startRouteButton(destination: SearchResult) -> some View {
        Button {
            isSearchFocused = false
            Task {
                await vm.startRoute()
            }
        } label: {
            HStack {
                Text(vm.routeDetails?.formattedTravelTime ?? "Start route")
                Image(systemName: "circle.fill")
                    .font(.system(size: 8))
                Text(destination.name)
                    .lineLimit(1)
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

    private var activeRouteControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                if let details = vm.routeDetails {
                    routeMetric(title: "ETA", value: details.formattedTravelTime)
                    routeMetric(title: "Distance", value: details.formattedDistance)
                }
            }

            Button(role: .destructive) {
                vm.stopNavigation()
            } label: {
                Text("End Route")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(32)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 32)
    }

    private func routeMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.headline)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(24)
        .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 4)
    }
}

#Preview {
    HomeView()
}
