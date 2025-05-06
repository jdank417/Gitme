// ContentView.swift
// Monolithic SwiftUI file for GitHub Insights iOS app

import SwiftUI
import Charts

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
    
    enum Tab: Hashable {
        case profile, activity, repos, metrics
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Username input
                HStack {
                    TextField("GitHub Username", text: $username, onCommit: {
                        viewModel.fetchAllData(username: username)
                    })
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                    Button(action: { viewModel.fetchAllData(username: username) }) {
                        Image(systemName: "arrow.clockwise.circle.fill")
                    }
                    .padding(.trailing)
                }
                Divider()
                // Tab View
                TabView(selection: $selectedTab) {
                    ProfileView(user: viewModel.user)
                        .tag(Tab.profile)
                        .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                    ContributionsHeatmapView(contributions: viewModel.contributions)
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
        }
        .onAppear {
            viewModel.fetchAllData(username: username)
        }
    }
}

// MARK: — Models
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

struct ContributionDay: Codable, Identifiable {
    let date: String
    let contributionCount: Int
    var id: String { date }
}

// MARK: — Networking
class GitHubAPI {
    static let shared = GitHubAPI()
    private let baseURL = "https://api.github.com"
    private let session: URLSession
    
    private init() {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .returnCacheDataElseLoad
        session = URLSession(configuration: config)
    }
    
    func fetchUser(username: String) async throws -> GitHubUser {
        let url = URL(string: "\(baseURL)/users/\(username)")!
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(GitHubUser.self, from: data)
    }

    func fetchRepos(username: String) async throws -> [GitHubRepo] {
        var all: [GitHubRepo] = []
        var page = 1
        while true {
            let url = URL(string: "\(baseURL)/users/\(username)/repos?per_page=100&page=\(page)")!
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { break }
            let repos = try JSONDecoder().decode([GitHubRepo].self, from: data)
            if repos.isEmpty { break }
            all += repos
            page += 1
        }
        return all
    }
    
    func fetchContributions(username: String) async throws -> [ContributionDay] {
        // Placeholder: use GraphQL or HTML scraping for real data
        return []
    }
}

// MARK: — ViewModel
@MainActor
class GitHubInsightsViewModel: ObservableObject {
    @Published var user: GitHubUser?
    @Published var repos: [GitHubRepo] = []
    @Published var contributions: [ContributionDay] = []
    @Published var errorMessage: String?
    
    func fetchAllData(username: String) {
        Task {
            do {
                user = try await GitHubAPI.shared.fetchUser(username: username)
                repos = try await GitHubAPI.shared.fetchRepos(username: username)
                contributions = try await GitHubAPI.shared.fetchContributions(username: username)
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
                    AsyncImage(url: u.avatar_url) { img in
                        img.resizable()
                    } placeholder: {
                        ProgressView()
                    }
                    .frame(width: 100, height: 100)
                    .clipShape(Circle())

                    Text(u.name ?? u.login)
                        .font(.title).bold()
                    if let bio = u.bio {
                        Text(bio)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    HStack(spacing: 20) {
                        InfoMetric(count: u.public_repos, label: "Repos")
                        InfoMetric(count: u.followers, label: "Followers")
                        InfoMetric(count: u.following, label: "Following")
                    }
                }
                .padding()
            } else {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct InfoMetric: View {
    let count: Int
    let label: String
    var body: some View {
        VStack {
            Text("\(count)")
                .font(.headline)
            Text(label).font(.subheadline)
        }
    }
}

struct ContributionsHeatmapView: View {
    let contributions: [ContributionDay]
    var body: some View {
        ScrollView {
            Chart(contributions) { c in
                BarMark(x: .value("Date", c.date), y: .value("Contributions", c.contributionCount))
            }
            .chartXAxis(.hidden)
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
                    if let lang = repo.language {
                        Text(lang).font(.subheadline)
                    }
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
                if !viewModel.repos.isEmpty {
                    Chart {
                        ForEach(languageStats(), id: \.language) { stat in
                            BarMark(x: .value("Language", stat.language), y: .value("Count", stat.count))
                        }
                    }
                    .frame(height: 200)
                }
                if !viewModel.contributions.isEmpty {
                    Chart {
                        ForEach(viewModel.contributions) { c in
                            LineMark(x: .value("Date", c.date), y: .value("Contributions", c.contributionCount))
                        }
                    }
                    .frame(height: 200)
                }
            }
            .padding()
        }
    }
    private func languageStats() -> [(language: String, count: Int)] {
        let langs = viewModel.repos.map { $0.language ?? "Unknown" }
        let counts = Dictionary(grouping: langs, by: { $0 }).mapValues { $0.count }
        return counts.sorted { $0.value > $1.value }.map { ($0.key, $0.value) }
    }
}
