// ContentView.swift
// Monolithic SwiftUI file for GitHub Insights iOS app

import SwiftUI
import Charts

// Shared DateFormatter for parsing dates
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

// MARK: — Data Models for Charts
struct ContributionPoint: Identifiable {
    let id: Date
    let count: Int
}

struct LanguageStat: Identifiable {
    let id: String
    let count: Int
}

// MARK: — App Entry
@main
struct GitHubInsightsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: — ContentView
struct ContentView: View {
    @StateObject private var viewModel = GitHubInsightsViewModel()
    @State private var username: String = "apple"
    @State private var selectedTab: Tab = .profile
    @State private var showError: Bool = false

    enum Tab: Hashable { case profile, activity, repos, metrics }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Username input
                HStack {
                    TextField("GitHub Username", text: $username)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .padding(.horizontal)
                        .onSubmit {
                            loadData()
                        }
                    Button(action: loadData) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                            .font(.title2)
                    }
                    .padding(.trailing)
                }
                Divider()

                // Tab View
                TabView(selection: $selectedTab) {
                    ProfileView(user: viewModel.user)
                        .tag(Tab.profile)
                        .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                    ContributionsHeatmapView(points: viewModel.contributionPoints)
                        .tag(Tab.activity)
                        .tabItem { Label("Activity", systemImage: "calendar") }
                    ReposListView(repos: viewModel.repos)
                        .tag(Tab.repos)
                        .tabItem { Label("Repos", systemImage: "folder") }
                    MetricsView(viewModel: viewModel)
                        .tag(Tab.metrics)
                        .tabItem { Label("Metrics", systemImage: "chart.bar") }
                }
            }
            .navigationTitle(username)
            .overlay {
                if viewModel.isLoading {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    ProgressView("Loading…").progressViewStyle(.circular)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
            .onChange(of: viewModel.errorMessage) { newValue in
                showError = newValue != nil
            }
        }
        .onAppear {
            loadData()
        }
    }

    private func loadData() {
        viewModel.fetchAllData(username: username)
    }
}

// MARK: — Network & Domain Models
struct GitHubUser: Codable {
    let login: String
    let avatar_url: URL
    let name: String?
    let bio: String?
    let public_repos: Int
    let followers: Int
    let following: Int
}

struct GitHubRepo: Codable, Identifiable {
    let id: Int
    let name: String
    let html_url: URL
    let stargazers_count: Int
    let forks_count: Int
    let language: String?
}

struct ContributionEvent: Codable {
    let type: String
    let created_at: String
}

class GitHubAPI {
    static let shared = GitHubAPI()
    private let baseURL = "https://api.github.com"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    func fetchUser(username: String) async throws -> GitHubUser {
        let url = URL(string: "\(baseURL)/users/\(username)")!
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(GitHubUser.self, from: data)
    }

    func fetchRepos(username: String) async throws -> [GitHubRepo] {
        var all = [GitHubRepo]()
        var page = 1
        while true {
            let url = URL(string: "\(baseURL)/users/\(username)/repos?per_page=100&page=\(page)")!
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { break }
            let repos = try JSONDecoder().decode([GitHubRepo].self, from: data)
            if repos.isEmpty { break }
            all += repos
            page += 1
        }
        return all
    }

    func fetchContributions(username: String) async throws -> [ContributionPoint] {
        let url = URL(string: "\(baseURL)/users/\(username)/events/public?per_page=100")!
        let (data, _) = try await session.data(from: url)
        let events = try JSONDecoder().decode([ContributionEvent].self, from: data)
        let dates = events.filter { $0.type == "PushEvent" }.compactMap { evt -> String? in
            guard let date = DateConstants.isoFormatter.date(from: evt.created_at) else { return nil }
            return DateConstants.dayFormatter.string(from: date)
        }
        let counts = Dictionary(grouping: dates, by: { $0 }).mapValues { $0.count }
        return counts.compactMap { day, count in
            guard let date = DateConstants.dayFormatter.date(from: day) else { return nil }
            return ContributionPoint(id: date, count: count)
        }.sorted { $0.id < $1.id }
    }
}

// MARK: — ViewModel
@MainActor
class GitHubInsightsViewModel: ObservableObject {
    @Published var user: GitHubUser?
    @Published var repos = [GitHubRepo]()
    @Published var contributionPoints = [ContributionPoint]()
    @Published var errorMessage: String?
    @Published var isLoading = false

    func fetchAllData(username: String) {
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                user = try await GitHubAPI.shared.fetchUser(username: username)
                repos = try await GitHubAPI.shared.fetchRepos(username: username)
                contributionPoints = try await GitHubAPI.shared.fetchContributions(username: username)
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: — Subviews
struct ProfileView: View {
    let user: GitHubUser?
    var body: some View {
        ScrollView {
            if let u = user {
                VStack(spacing: 16) {
                    AsyncImage(url: u.avatar_url) { img in img.resizable() } placeholder: { ProgressView() }
                        .frame(width: 100, height: 100).clipShape(Circle())
                    Text(u.name ?? u.login).font(.title).bold()
                    if let bio = u.bio { Text(bio).font(.body).multilineTextAlignment(.center).padding(.horizontal) }
                    HStack(spacing: 20) {
                        InfoMetric(count: u.public_repos, label: "Repos")
                        InfoMetric(count: u.followers, label: "Followers")
                        InfoMetric(count: u.following, label: "Following")
                    }
                }
                .padding()
            } else {
                ProgressView("Loading Profile…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct InfoMetric: View {
    let count: Int
    let label: String
    var body: some View {
        VStack { Text("\(count)").font(.headline); Text(label).font(.subheadline) }
    }
}

struct ContributionsHeatmapView: View {
    let points: [ContributionPoint]
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Chart(points) { pt in
                BarMark(x: .value("Date", pt.id), y: .value("Contributions", pt.count))
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) }
            .frame(height: 200)
            .padding()
        }
    }
}

struct ReposListView: View {
    let repos: [GitHubRepo]
    var body: some View {
        List(repos) { repo in
            VStack(alignment: .leading) {
                Text(repo.name).font(.headline)
                HStack {
                    Label("\(repo.stargazers_count)", systemImage: "star.fill").font(.subheadline)
                    Label("\(repo.forks_count)", systemImage: "tuningfork").font(.subheadline)
                    if let lang = repo.language { Text(lang).font(.subheadline) }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

struct MetricsView: View {
    @ObservedObject var viewModel: GitHubInsightsViewModel
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Language Stats
                let stats = Dictionary(grouping: viewModel.repos.map { $0.language ?? "Unknown" }, by: { $0 })
                    .map { LanguageStat(id: $0.key, count: $0.value.count) }
                    .sorted { $0.count > $1.count }
                if !stats.isEmpty {
                    Chart(stats) { stat in
                        BarMark(x: .value("Language", stat.id), y: .value("Count", stat.count))
                    }
                    .frame(height: 200)
                }

                // Contribution Timeline
                if !viewModel.contributionPoints.isEmpty {
                    Chart(viewModel.contributionPoints) { pt in
                        LineMark(x: .value("Date", pt.id), y: .value("Contributions", pt.count))
                    }
                    .frame(height: 200)
                }
            }
            .padding()
        }
    }
}
