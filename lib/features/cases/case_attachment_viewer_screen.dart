import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart' as pdfviewer;
import 'package:share_plus/share_plus.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;

import '../../core/widgets/compact_search_field.dart';
import '../../core/widgets/global_settings_button.dart';

const int _largePdfExtractionWarningBytes = 40 * 1024 * 1024;

Future<String> _extractPdfTextOffMainIsolate(String filePath) => Isolate.run(() {
      final bytes = File(filePath).readAsBytesSync();
      final document = sfpdf.PdfDocument(inputBytes: bytes);
      try {
        return sfpdf.PdfTextExtractor(document).extractText().trim();
      } finally {
        document.dispose();
      }
    });

String _humanReadableFileSize(int bytes) {
  if (bytes < 1024) return '$bytes بایت';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} کیلوبایت';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(1)} مگابایت';
  return '${(mb / 1024).toStringAsFixed(2)} گیگابایت';
}

class CaseAttachmentViewerScreen extends StatelessWidget {
  const CaseAttachmentViewerScreen({
    super.key,
    required this.filePath,
    required this.title,
    this.fileType,
  });

  final String filePath;
  final String title;
  final String? fileType;

  bool get _isPdf => (fileType ?? '').toLowerCase() == 'pdf' || p.extension(filePath).toLowerCase() == '.pdf';

  bool get _isImage {
    final ext = p.extension(filePath).toLowerCase();
    return (fileType ?? '').toLowerCase() == 'image' || ['.jpg', '.jpeg', '.png', '.webp', '.bmp', '.gif'].contains(ext);
  }

  Future<void> _share(BuildContext context) async {
    final file = File(filePath);
    if (!await file.exists()) {
      if (context.mounted) _showMessage(context, 'فایل اصلی پیدا نشد.');
      return;
    }
    await Share.shareXFiles(
      [XFile(filePath)],
      text: title,
      subject: title,
      sharePositionOrigin: const Rect.fromLTWH(0, 0, 100, 100),
    );
  }

  Future<void> _openExternal(BuildContext context) async {
    final file = File(filePath);
    if (!await file.exists()) {
      if (context.mounted) _showMessage(context, 'فایل اصلی پیدا نشد.');
      return;
    }
    final result = await OpenFilex.open(filePath);
    if (context.mounted && result.message.isNotEmpty) {
      _showMessage(context, result.message);
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final fileName = p.basename(filePath);
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          const GlobalSettingsButton(),
          IconButton(
            tooltip: 'اشتراک‌گذاری فایل اصلی',
            icon: const Icon(Icons.share),
            onPressed: () => _share(context),
          ),
          IconButton(
            tooltip: 'باز کردن با برنامه دیگر',
            icon: const Icon(Icons.open_in_new),
            onPressed: () => _openExternal(context),
          ),
        ],
      ),
      body: FutureBuilder<bool>(
        future: File(filePath).exists(),
        builder: (context, snapshot) {
          final exists = snapshot.data == true;
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!exists) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('فایل اصلی پیدا نشد.\n$fileName', textAlign: TextAlign.center),
              ),
            );
          }
          if (_isPdf) return _PdfAttachmentViewer(filePath: filePath);
          if (_isImage) return _ImageAttachmentViewer(filePath: filePath);
          return _UnknownAttachmentViewer(filePath: filePath, onOpenExternal: () => _openExternal(context));
        },
      ),
    );
  }
}



class _PdfAttachmentViewer extends StatefulWidget {
  const _PdfAttachmentViewer({required this.filePath});

  final String filePath;

  @override
  State<_PdfAttachmentViewer> createState() => _PdfAttachmentViewerState();
}

class _PdfAttachmentViewerState extends State<_PdfAttachmentViewer> {
  late final pdfviewer.PdfViewerController _pdfViewerController;
  final TextEditingController _searchController = TextEditingController();
  pdfviewer.PdfTextSearchResult _searchResult = pdfviewer.PdfTextSearchResult();
  int _page = 1;
  int _pagesCount = 0;
  String? _extractedText;
  String? _searchMessage;
  bool _extracting = false;
  bool _searching = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _pdfViewerController = pdfviewer.PdfViewerController();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchResult.removeListener(_handleSearchResultChanged);
    _searchResult.clear();
    _pdfViewerController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<bool> _confirmLargePdfExtraction(int sizeBytes) async {
    if (sizeBytes < _largePdfExtractionWarningBytes) return true;
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('PDF حجیم است'),
            content: Text(
              'حجم فایل ${_humanReadableFileSize(sizeBytes)} است. نمایش خود PDF ادامه دارد، اما استخراج کامل متن ممکن است زمان‌بر باشد و حافظه بیشتری مصرف کند. ادامه می‌دهید؟',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('انصراف')),
              FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('استخراج متن')),
            ],
          ),
        ) ??
        false;
  }

  Future<String> _extractText() async {
    final cached = _extractedText;
    if (cached != null) return cached;
    final file = File(widget.filePath);
    final sizeBytes = await file.length();
    if (!await _confirmLargePdfExtraction(sizeBytes)) return '';
    if (mounted) setState(() => _extracting = true);
    try {
      // پردازش متن PDF در isolate جدا انجام می‌شود تا رابط کاربری هنگام فایل‌های
      // طولانی یا اسکن‌شده مسدود نشود. فایل اصلی هیچ تغییری نمی‌کند.
      final text = await _extractPdfTextOffMainIsolate(widget.filePath);
      _extractedText = text;
      return text;
    } catch (_) {
      return '';
    } finally {
      if (mounted) setState(() => _extracting = false);
    }
  }

  Future<void> _showExtractedText() async {
    final text = await _extractText();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(sheetContext).padding.bottom + 16),
          child: SizedBox(
            height: MediaQuery.of(sheetContext).size.height * 0.75,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(child: Text('متن استخراج‌شده PDF', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                    IconButton(onPressed: () => Navigator.pop(sheetContext), icon: const Icon(Icons.close)),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: text.isEmpty
                      ? const Center(child: Text('متنی از این PDF استخراج نشد. اگر فایل اسکن‌شده باشد، برای استخراج متن به OCR نیاز دارد.'))
                      : SingleChildScrollView(child: SelectableText(text, textAlign: TextAlign.justify)),
                ),
                if (text.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: text));
                      if (sheetContext.mounted) Navigator.pop(sheetContext);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('متن PDF کپی شد.')));
                      }
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('کپی متن'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleSearchResultChanged() {
    if (!mounted) return;
    setState(() {
      _searching = !_searchResult.isSearchCompleted && !_searchResult.hasResult;
      _searchMessage = _formatSearchMessage();
    });
  }

  String _formatSearchMessage() {
    final query = _searchController.text.trim();
    if (_searchResult.hasResult && _searchResult.totalInstanceCount > 0) {
      final current = _searchResult.currentInstanceIndex <= 0 ? 1 : _searchResult.currentInstanceIndex;
      return '$current از ${_searchResult.totalInstanceCount} نتیجه؛ مورد جاری داخل خود PDF هایلایت شده است.';
    }
    if (_searchResult.isSearchCompleted && _searchResult.totalInstanceCount == 0) {
      return 'عبارت «$query» داخل متن PDF پیدا نشد. اگر فایل اسکن‌شده باشد، برای جستجو و هایلایت به OCR نیاز دارد.';
    }
    return 'در حال جستجو و هایلایت داخل PDF...';
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) {
      _clearSearch();
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 180), _searchText);
  }

  void _searchText() {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    _searchResult.removeListener(_handleSearchResultChanged);
    _searchResult.clear();
    final result = _pdfViewerController.searchText(query);
    result.addListener(_handleSearchResultChanged);
    setState(() {
      _searchResult = result;
      _searching = true;
      _searchMessage = 'در حال جستجو و هایلایت داخل PDF...';
    });
    _handleSearchResultChanged();
  }

  void _clearSearch() {
    _searchResult.removeListener(_handleSearchResultChanged);
    _searchResult.clear();
    setState(() {
      _searchResult = pdfviewer.PdfTextSearchResult();
      _searching = false;
      _searchMessage = null;
    });
  }

  void _previousSearchResult() {
    if (!_searchResult.hasResult) return;
    _searchResult.previousInstance();
    _handleSearchResultChanged();
  }

  void _nextSearchResult() {
    if (!_searchResult.hasResult) return;
    _searchResult.nextInstance();
    _handleSearchResultChanged();
  }

  @override
  Widget build(BuildContext context) {
    final hasSearchResult = _searchResult.hasResult && _searchResult.totalInstanceCount > 0;
    return Column(
      children: [
        Material(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      tooltip: 'صفحه قبل',
                      onPressed: _page <= 1
                          ? null
                          : () => _pdfViewerController.previousPage(),
                      icon: const Icon(Icons.chevron_right),
                    ),
                    Expanded(
                      child: Text(
                        _pagesCount == 0 ? 'در حال بارگذاری PDF' : 'صفحه $_page از $_pagesCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: 'صفحه بعد',
                      onPressed: _pagesCount > 0 && _page >= _pagesCount
                          ? null
                          : () => _pdfViewerController.nextPage(),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    IconButton(
                      tooltip: 'استخراج متن',
                      onPressed: _extracting ? null : _showExtractedText,
                      icon: _extracting
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.text_snippet),
                    ),
                  ],
                ),
                FutureBuilder<int>(
                  future: File(widget.filePath).length(),
                  builder: (context, snapshot) => Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      snapshot.hasData ? 'حجم فایل: ${_humanReadableFileSize(snapshot.data!)}' : 'در حال خواندن مشخصات فایل...',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                CompactSearchField(
                  controller: _searchController,
                  hintText: 'جستجو و هایلایت داخل PDF...',
                  onChanged: _onSearchChanged,
                  onSubmitted: (_) => _searchText(),
                ),
                if (_searchMessage != null || hasSearchResult)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _searchMessage ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      IconButton(
                        tooltip: 'نتیجه قبلی',
                        visualDensity: VisualDensity.compact,
                        onPressed: hasSearchResult ? _previousSearchResult : null,
                        icon: const Icon(Icons.keyboard_arrow_up),
                      ),
                      IconButton(
                        tooltip: 'نتیجه بعدی',
                        visualDensity: VisualDensity.compact,
                        onPressed: hasSearchResult ? _nextSearchResult : null,
                        icon: const Icon(Icons.keyboard_arrow_down),
                      ),
                    ],
                  ),

              ],
            ),
          ),
        ),
        if (_searching) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: pdfviewer.SfPdfViewer.file(
            File(widget.filePath),
            controller: _pdfViewerController,
            // هایلایت کم‌رنگ و شفاف باشد تا متن PDF زیر آن خوانا بماند.
            currentSearchTextHighlightColor: const Color(0x66FFEB3B),
            otherSearchTextHighlightColor: const Color(0x33FFF176),
            onDocumentLoaded: (details) {
              if (!mounted) return;
              setState(() => _pagesCount = details.document.pages.count);
            },
            onPageChanged: (details) {
              if (!mounted) return;
              setState(() => _page = details.newPageNumber);
            },
            onDocumentLoadFailed: (details) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('نمایش PDF انجام نشد: ${details.description}')));
            },
          ),
        ),
      ],
    );
  }
}

class _ImageAttachmentViewer extends StatefulWidget {
  const _ImageAttachmentViewer({required this.filePath});

  final String filePath;

  @override
  State<_ImageAttachmentViewer> createState() => _ImageAttachmentViewerState();
}

class _ImageAttachmentViewerState extends State<_ImageAttachmentViewer> {
  int _turns = 0;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          elevation: 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: FutureBuilder<int>(
                    future: File(widget.filePath).length(),
                    builder: (context, snapshot) => Text(
                      snapshot.hasData
                          ? 'نمایش عکس با کیفیت اصلی — ${_humanReadableFileSize(snapshot.data!)}'
                          : 'نمایش عکس با کیفیت اصلی',
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'چرخش تصویر',
                  icon: const Icon(Icons.rotate_right),
                  onPressed: () => setState(() => _turns = (_turns + 1) % 4),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 8,
            child: Center(
              child: RotatedBox(
                quarterTurns: _turns,
                child: Image.file(
                  File(widget.filePath),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('نمایش عکس انجام نشد.'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _UnknownAttachmentViewer extends StatelessWidget {
  const _UnknownAttachmentViewer({required this.filePath, required this.onOpenExternal});

  final String filePath;
  final VoidCallback onOpenExternal;

  @override
  Widget build(BuildContext context) {
    final fileName = p.basename(filePath);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file, size: 48),
            const SizedBox(height: 12),
            Text(fileName, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('این نوع فایل داخل کوروش‌یار قابل نمایش مستقیم نیست. می‌توانید آن را با یکی از برنامه‌های گوشی باز کنید یا فایل اصلی را اشتراک‌گذاری کنید.', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onOpenExternal,
              icon: const Icon(Icons.open_in_new),
              label: const Text('باز کردن با برنامه دیگر'),
            ),
          ],
        ),
      ),
    );
  }
}
