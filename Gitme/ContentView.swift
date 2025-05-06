// ContentView.swift
// Monolithic SwiftUI file for GitHub Insights iOS app (UI Enhancements Only)
// Current Date: Monday, May 5, 2025 at 11:47:19 PM EDT

import SwiftUI
import Charts

// Shared DateFormatter for parsing dates (No changes)
enum DateConstants {
    static let isoFormatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return fmt
    }()
    static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()
}

// MARK: — Data Models for Charts (No changes)
struct ContributionPoint: Identifiable {
    let id: Date
    let count: Int
}
struct LanguageStat: Identifiable {
    let id: String
    let count: Int
    // Added helper for display name
    var languageDisplayName: String { id == "Unknown" ? "Other/Unknown" : id }
}

// MARK: — App Entry (No changes)
@main
struct GitHubInsightsApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

// MARK: — ContentView (UI Enhancements)
struct ContentView: View {
    @StateObject private var viewModel = GitHubInsightsViewModel()
    @State private var username: String = "apple"
    @State private var selectedTab: Tab = .profile
    @State private var showError: Bool = false

    enum Tab: Hashable { case profile, activity, repos, metrics }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // --- Enhanced Input Header ---
                HStack {
                    TextField("GitHub Username", text: $username)
                        .textFieldStyle(.plain) // Use plain style for custom background
                        .padding(10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8)) // Use material background
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .submitLabel(.search) // Add submit label
                        .onSubmit {
                            hideKeyboard()
                            loadData()
                        }

                    Button {
                        hideKeyboard()
                        loadData()
                    } label: {
                        // Change icon based on loading state
                        Image(systemName: viewModel.isLoading ? "arrow.triangle.2.circlepath.circle.fill" : "magnifyingglass.circle.fill")
                            .font(.title2)
                            .foregroundColor(viewModel.isLoading ? .secondary : .accentColor) // Indicate loading
                    }
                    // Disable button while loading or if username is empty
                    .disabled(viewModel.isLoading || username.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .background(.bar) // Use bar background for header area

                // Use TabView without Divider
                TabView(selection: $selectedTab) {
                    ProfileView(user: viewModel.user) // Enhanced View
                        .tag(Tab.profile)
                        .tabItem { Label("Profile", systemImage: "person.crop.circle") }

                    // Use enhanced & renamed ContributionsActivityView
                    ContributionsActivityView(points: viewModel.contributionPoints)
                        .tag(Tab.activity)
                        .tabItem { Label("Activity", systemImage: "chart.bar.xaxis") } // More fitting icon

                    ReposListView(repos: viewModel.repos) // Enhanced View
                        .tag(Tab.repos)
                        .tabItem { Label("Repos", systemImage: "folder") }

                    MetricsView(viewModel: viewModel) // Enhanced View
                        .tag(Tab.metrics)
                        .tabItem { Label("Metrics", systemImage: "chart.pie") } // More fitting icon
                }
                // Add refreshable here for pull-to-refresh
                 .refreshable {
                     await loadDataAsync()
                 }

            }
            // Use username from loaded user if available for title
            .navigationTitle(viewModel.user?.name ?? viewModel.user?.login ?? username)
            .navigationBarTitleDisplayMode(.inline) // Keep title small
            .overlay { // Enhanced Loading Overlay
                if viewModel.isLoading {
                    ZStack {
                        // Semi-transparent background
                        Color.black.opacity(0.1).ignoresSafeArea()
                        ProgressView("Loading…")
                            .padding(20)
                            .background(.regularMaterial) // Use material background
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: .black.opacity(0.2), radius: 5, x: 0, y: 2)
                    }
                }
            }
            .alert("Error", isPresented: $showError) { // Standard Alert
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
            .onChange(of: viewModel.errorMessage) { newValue in
                showError = newValue != nil
            }
        }
        .navigationViewStyle(.stack) // Use stack style
        .onAppear {
            // Load initial data only if user isn't already loaded
            if viewModel.user == nil {
                loadData()
            }
        }
    }

    private func loadData() {
        hideKeyboard()
        viewModel.fetchAllData(username: username.trimmingCharacters(in: .whitespaces))
    }

    // Async version needed for refreshable
    private func loadDataAsync() async {
        // Accessing @MainActor ViewModel function is safe
         viewModel.fetchAllData(username: username.trimmingCharacters(in: .whitespaces))
    }

    // Helper to dismiss keyboard
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

// MARK: — Network & Domain Models (No changes)
struct GitHubUser: Codable { let login: String; let avatar_url: URL; let name: String?; let bio: String?; let public_repos: Int; let followers: Int; let following: Int }
struct GitHubRepo: Codable, Identifiable { let id: Int; let name: String; let html_url: URL; let description: String? = nil; let stargazers_count: Int; let forks_count: Int; let language: String? } // Added default nil for description
struct ContributionEvent: Codable { let type: String; let created_at: String }

// MARK: — Networking Class (No changes)
class GitHubAPI {
    static let shared = GitHubAPI(); private let baseURL = "https://api.github.com"; private let session: URLSession
    private init(){let c = URLSessionConfiguration.default; c.requestCachePolicy = .reloadIgnoringLocalCacheData; session = URLSession(configuration:c)}
    func fetchUser(username:String)async throws->GitHubUser{let u=URL(string:"\(baseURL)/users/\(username)")!;let(d,_)=try await session.data(from:u);return try JSONDecoder().decode(GitHubUser.self,from:d)}
    func fetchRepos(username:String)async throws->[GitHubRepo]{var a=[GitHubRepo]();var p=1;while true{let u=URL(string:"\(baseURL)/users/\(username)/repos?per_page=100&page=\(p)")!;let(d,r)=try await session.data(from:u);guard(r as?HTTPURLResponse)?.statusCode==200 else{break};let rs=try JSONDecoder().decode([GitHubRepo].self,from:d);if rs.isEmpty{break};a+=rs;p+=1};return a}
    func fetchContributions(username:String)async throws->[ContributionPoint]{let u=URL(string:"\(baseURL)/users/\(username)/events/public?per_page=100")!;let(d,_)=try await session.data(from:u);let es=try JSONDecoder().decode([ContributionEvent].self,from:d);let ds=es.filter{$0.type=="PushEvent"}.compactMap{e->String? in guard let dt=DateConstants.isoFormatter.date(from:e.created_at)else{return nil};return DateConstants.dayFormatter.string(from:dt)};let cs=Dictionary(grouping:ds,by:{$0}).mapValues{$0.count};return cs.compactMap{day,count in guard let dt=DateConstants.dayFormatter.date(from:day)else{return nil};return ContributionPoint(id:dt,count:count)}.sorted{$0.id < $1.id}}
}

// MARK: — ViewModel (No changes)
@MainActor
class GitHubInsightsViewModel: ObservableObject {
    @Published var user: GitHubUser?; @Published var repos = [GitHubRepo](); @Published var contributionPoints = [ContributionPoint](); @Published var errorMessage: String?; @Published var isLoading = false
    func fetchAllData(username:String){isLoading=true;Task{defer{isLoading=false};do{user=try await GitHubAPI.shared.fetchUser(username:username);repos=try await GitHubAPI.shared.fetchRepos(username:username);contributionPoints=try await GitHubAPI.shared.fetchContributions(username:username);errorMessage=nil}catch{errorMessage=error.localizedDescription}}}
}


// MARK: — Subviews (UI Enhancements)

// --- Profile Tab ---
struct ProfileView: View {
    let user: GitHubUser?
    var body: some View {
        ScrollView {
            // Use ContentUnavailableView if user is nil after attempted load (handles initial state too)
             if let u = user {
                VStack(spacing: 20) { // Increased spacing
                    AsyncImage(url: u.avatar_url) { phase in // Enhanced AsyncImage
                        switch phase {
                        case .empty:
                            ProgressView().frame(width: 120, height: 120) // Larger placeholder
                        case .success(let image):
                            image.resizable().aspectRatio(contentMode: .fill)
                        case .failure:
                            // Nicer error placeholder
                            Image(systemName: "person.crop.circle.badge.exclamationmark")
                                .resizable().aspectRatio(contentMode: .fit)
                                .frame(width: 120, height: 120).foregroundColor(.secondary)
                        @unknown default: EmptyView()
                        }
                    }
                    .frame(width: 120, height: 120) // Larger avatar
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1)) // Subtle overlay
                    .shadow(radius: 5) // Add shadow

                    VStack { // Group name and login
                        Text(u.name ?? u.login).font(.title2).bold() // Slightly smaller title
                        Text("@\(u.login)").font(.subheadline).foregroundColor(.secondary)
                    }

                    if let bio = u.bio, !bio.isEmpty {
                        Text(bio).font(.body).multilineTextAlignment(.center).padding(.horizontal)
                            .foregroundColor(.secondary) // Softer bio color
                    }

                    // Use Grid for metrics for better alignment if many items
                     HStack(alignment: .center, spacing: 30) { // Keep HStack if only 3
                        InfoMetric(count: u.public_repos, label: "Repos")
                        InfoMetric(count: u.followers, label: "Followers")
                        InfoMetric(count: u.following, label: "Following")
                    }.padding(.top) // Add padding above metrics

                }.padding(.vertical, 20) // Add vertical padding to whole VStack
            } else {
                // Use ContentUnavailableView for empty/initial state
                 ContentUnavailableView(
                     "Enter Username",
                     systemImage: "person.fill.questionmark",
                     description: Text("Enter a GitHub username above and tap search.")
                 )
                 .padding(.top, 50) // Push down slightly
            }
        }
        .background(Color(.systemGroupedBackground)) // Subtle background for the profile page
         .navigationTitle("Profile") // Set title for clarity, overridden by main view later
         .navigationBarTitleDisplayMode(.inline)
    }
}

struct InfoMetric: View {
    let count: Int
    let label: String
    var body: some View {
        VStack(spacing: 4) { // Increased spacing slightly
            Text("\(count)")
                .font(.headline)
                .fontWeight(.semibold) // Bolder count
            Text(label)
                .font(.caption) // Standard caption size
                .foregroundColor(.secondary)
        }
    }
}

// --- Activity Tab ---
// Renamed struct, added UI enhancements
struct ContributionsActivityView: View {
    let points: [ContributionPoint]

    // Calculate range for chart scaling
    private var contributionRange: ClosedRange<Int> {
        let counts = points.map { $0.count }
        let maxVal = counts.max() ?? 0
        return 0...(Swift.max(1, maxVal)) // Ensure range is at least 0...1
    }

    var body: some View {
        Group { // Use group to switch between chart and placeholder
            if points.isEmpty {
                ContentUnavailableView(
                    "No Recent Activity",
                    systemImage: "chart.bar.xaxis.ascending.badge.clock",
                    description: Text("No recent public push events found.")
                )
            } else {
                Chart(points) { pt in
                    BarMark(
                        x: .value("Date", pt.id, unit: .day), // Specify unit
                        y: .value("Contributions", pt.count)
                    )
                    // Use gradient fill for bars
                    .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.green.opacity(0.3), .green]), startPoint: .bottom, endPoint: .top))
                     .cornerRadius(4) // Slightly rounded bars
                }
                // Enhanced Axis formatting
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 7)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3])) // Dashed grid lines
                        AxisTick()
                        // Format date labels clearly
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: false)
                    }
                }
                .chartYAxis {
                    AxisMarks(preset: .automatic, values: .automatic(desiredCount: 5)) { value in
                         AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 3]))
                         AxisValueLabel() // Default numeric labels suffice
                    }
                }
                // Add slight padding to the top of Y-axis
                 .chartYScale(domain: 0...(contributionRange.upperBound + 1))
                 .chartPlotStyle { plotArea in // Add background to plot area
                      plotArea.background(.quaternary.opacity(0.1))
                  }
                 .padding() // Padding around the chart
                 .navigationTitle("Contribution Activity") // Title for this specific view
                 .navigationBarTitleDisplayMode(.inline)
            }
        }
        .background(Color(.systemGroupedBackground)) // Match profile background
    }
}


// --- Repos Tab ---
struct ReposListView: View {
    let repos: [GitHubRepo]
    var body: some View {
        Group {
            if repos.isEmpty {
                 ContentUnavailableView(
                     "No Repositories",
                     systemImage: "folder.badge.questionmark",
                     description: Text("This user has no public repositories found.")
                 )
            } else {
                // Use List with extracted Row View
                List(repos) { repo in
                    // Link wraps the entire row
                     Link(destination: repo.html_url) {
                        RepoRow(repo: repo)
                    }
                     .listRowSeparator(.hidden) // Hide default separators if RepoRow has its own
                }
                 .listStyle(.plain) // Use plain style for edge-to-edge look if desired
                 // .listStyle(.insetGrouped) // Or grouped for visual separation
            }
        }
         .navigationTitle("Repositories")
         .navigationBarTitleDisplayMode(.inline)
    }
}

// Extracted Row View for Repositories
struct RepoRow: View {
    let repo: GitHubRepo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { // Added spacing
            Text(repo.name)
                .font(.headline)
                .fontWeight(.semibold) // Make name stand out
                .foregroundColor(.primary)

            // Show description if available
            if let description = repo.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline) // Use subheadline for description
                    .foregroundColor(.secondary)
                    .lineLimit(2) // Limit lines
            }

            // Stats row
            HStack(spacing: 16) { // Consistent spacing
                Label { Text("\(repo.stargazers_count)") } icon: { Image(systemName: "star.fill") }
                    .foregroundColor(.orange) // Color for stars
                Label { Text("\(repo.forks_count)") } icon: { Image(systemName: "tuningfork") }
                    .foregroundColor(.blue) // Color for forks
                if let lang = repo.language {
                    // Language label with color indicator
                     Label { Text(lang) } icon: { Image(systemName: "circle.fill").font(.caption2) } // Smaller circle
                        .font(.caption) // Consistent caption font
                        .foregroundStyle(languageColor(lang).gradient) // Use gradient for color
                         .padding(.horizontal, 6).padding(.vertical, 3) // Padding for tag-like look
                         .background(languageColor(lang).opacity(0.15), in: Capsule()) // Background capsule
                }
            }
            .font(.caption) // Apply caption style to the HStack content
            .padding(.top, 4) // Add slight space above stats

        }
        .padding(.vertical, 10) // Add vertical padding to the row content
        // Add subtle background per row and divider if using .plain list style
         .listRowBackground(Color(.secondarySystemGroupedBackground))
         .overlay(Divider().padding(.leading, 0), alignment: .bottom) // Manual divider
    }

    // Simple function for language coloring (add more!)
    private func languageColor(_ language: String) -> Color {
        switch language.lowercased() {
            case "swift": .orange
            case "javascript", "typescript": .yellow
            case "python": .blue
            case "java", "kotlin": .red
            case "html": .pink
            case "css": .purple
            case "ruby": .red
            case "c#", "c++", "c": .gray
            case "go": .cyan
            case "php": .indigo
            case "shell": .green
            default: .secondary
        }
    }
}


// --- Metrics Tab ---
struct MetricsView: View {
    // NOTE: Calculation logic remains here per request
    @ObservedObject var viewModel: GitHubInsightsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) { // Increased spacing between sections
                // Calculate stats here (as requested)
                 let languageStats = Dictionary(grouping: viewModel.repos.map { $0.language ?? "Unknown" }, by: { $0 })
                    .map { LanguageStat(id: $0.key, count: $0.value.count) }
                    .sorted { $0.count > $1.count }

                // Language Chart Section
                 if !languageStats.isEmpty {
                     LanguageChartView(stats: languageStats)
                 } else {
                      VStack(alignment: .leading) { // Wrap placeholder in VStack for alignment
                          Text("Language Distribution").font(.title3).bold().padding(.bottom, 5)
                          ContentUnavailableView("No Language Data", systemImage: "chart.pie").frame(height: 200)
                      }
                 }

                 Divider() // Add divider between sections

                 // Contribution Timeline Section
                 if !viewModel.contributionPoints.isEmpty {
                     ContributionTimelineView(points: viewModel.contributionPoints)
                 } else {
                     VStack(alignment: .leading) { // Wrap placeholder
                          Text("Contribution Timeline").font(.title3).bold().padding(.bottom, 5)
                          ContentUnavailableView("No Activity Data", systemImage: "chart.xyaxis.line").frame(height: 200)
                     }
                 }
            }
            .padding() // Padding around the main VStack
        }
        .background(Color(.systemGroupedBackground)) // Consistent background
        .navigationTitle("Metrics")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// Extracted Chart Views for Metrics Tab
struct LanguageChartView: View {
    let stats: [LanguageStat]
    private let maxLanguagesToShow = 7 // Limit languages shown

    // Group less frequent languages into "Other"
    private var chartData: [LanguageStat] {
        guard !stats.isEmpty else { return [] }
        if stats.count <= maxLanguagesToShow { return stats }
        else {
            let topStats = Array(stats.prefix(maxLanguagesToShow))
            let otherCount = stats.dropFirst(maxLanguagesToShow).reduce(0) { $0 + $1.count }
            if otherCount > 0 { return topStats + [LanguageStat(id: "Other", count: otherCount)] }
            else { return topStats }
        }
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text("Language Distribution") // Section header
                .font(.title3).bold()
                .padding(.bottom, 8)

            // Horizontal Bar Chart for better label readability
            Chart(chartData) { stat in
                BarMark(
                    x: .value("Count", stat.count),
                    y: .value("Language", stat.languageDisplayName) // Use computed property for label
                )
                .foregroundStyle(by: .value("Language", stat.languageDisplayName)) // Color code bars
                .annotation(position: .trailing, alignment: .leading) { // Show count value
                    Text("\(stat.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .chartLegend(.hidden) // Hide legend if colors/labels are clear
            // Dynamic height based on number of bars
            .frame(height: max(120, CGFloat(chartData.count) * 40)) // Ensure minimum height
        }
    }
}

struct ContributionTimelineView: View {
    let points: [ContributionPoint]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Contribution Timeline") // Section header
                .font(.title3).bold()
                .padding(.bottom, 8)

            Chart(points) { pt in
                // Line chart for trend
                LineMark(
                    x: .value("Date", pt.id, unit: .day),
                    y: .value("Contributions", pt.count)
                )
                .interpolationMethod(.catmullRom) // Smoothed line
                .foregroundStyle(.blue.gradient) // Use gradient color

                // Optional: Area under the line
                 AreaMark(
                     x: .value("Date", pt.id, unit: .day),
                     y: .value("Contributions", pt.count)
                 )
                 .interpolationMethod(.catmullRom)
                 .foregroundStyle(LinearGradient(gradient: Gradient(colors: [.blue.opacity(0.3), .blue.opacity(0.0)]), startPoint: .top, endPoint: .bottom)) // Fading gradient area
            }
            // Format axes
            .chartXAxis { AxisMarks(preset: .automatic, values: .automatic(desiredCount: 5)) { v in AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.month(.narrow).day()) } }
            .chartYAxis { AxisMarks(preset: .automatic, values: .automatic(desiredCount: 4)) }
            .frame(height: 200) // Consistent height
        }
    }
}
