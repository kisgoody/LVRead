import Foundation
import Combine

// MARK: - Bookshelf ViewModel

final class BookshelfViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var books: [Book] = []
    @Published private(set) var filteredBooks: [Book] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var error: String?
    
    @Published var searchText: String = "" {
        didSet { applyFilters() }
    }
    @Published var currentSort: BookSortType = .recentRead {
        didSet { loadBooks() }
    }
    @Published var progressFilter: ReadingProgressFilter = .all {
        didSet { applyFilters() }
    }
    @Published var sourceFilter: BookSource? {
        didSet { applyFilters() }
    }
    @Published var formatFilter: FileFormat? {
        didSet { applyFilters() }
    }

    // MARK: - Private Properties

    private var cancellables = Set<AnyCancellable>()
    private let bookRepository = BookRepository.shared

    // MARK: - Initialization

    init() {
        setupBindings()
    }

    // MARK: - Setup

    private func setupBindings() {
        // Listen for book import notifications
        NotificationCenter.default.publisher(for: .bookImported)
            .sink { [weak self] _ in
                self?.loadBooks()
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    func loadBooks() {
        isLoading = true
        error = nil

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let allBooks = self.bookRepository.getAll(sortBy: self.currentSort)
            
            DispatchQueue.main.async {
                self.books = allBooks
                self.isLoading = false
                self.applyFilters()
            }
        }
    }

    func deleteBook(_ book: Book) {
        let result = bookRepository.delete(book.id)
        switch result {
        case .success:
            loadBooks()
        case .failure(let err):
            error = err.localizedDescription
        }
    }

    func deleteBooks(_ bookIds: [String]) {
        let result = bookRepository.deleteBatch(bookIds)
        switch result {
        case .success:
            loadBooks()
        case .failure(let err):
            error = err.localizedDescription
        }
    }

    func updateBook(_ book: Book) {
        _ = bookRepository.update(book)
        loadBooks()
    }

    func searchBooks(query: String) {
        searchText = query
    }

    func clearError() {
        error = nil
    }

    // MARK: - Private Methods

    private func applyFilters() {
        var result = books

        // Apply search filter
        if !searchText.isEmpty {
            result = result.filter {
                $0.title.localizedCaseInsensitiveContains(searchText) ||
                $0.author.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Apply progress filter
        if progressFilter != .all {
            result = result.filter { progressFilter.matches($0.readingProgress) }
        }

        // Apply source filter
        if let source = sourceFilter {
            result = result.filter { $0.source == source }
        }

        // Apply format filter
        if let format = formatFilter {
            result = result.filter { $0.fileFormat == format }
        }

        filteredBooks = result
    }

    // MARK: - Computed Properties

    var bookCount: Int {
        filteredBooks.count
    }

    var hasBooks: Bool {
        !filteredBooks.isEmpty
    }

    var isEmpty: Bool {
        filteredBooks.isEmpty && !isLoading
    }
}
