// نمونه‌ی تب لغات:
Column(
  children: [
    const FilterBar(searchHint: 'جستجوی لغت...'),
    Expanded(
      child: filteredWords.isEmpty
          ? PlaceholderTab(...)   // خالی
          : ListView(...),        // لیست
    ),
  ],
)
