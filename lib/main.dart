import 'dart:html' as html;
import 'dart:collection';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '"My Clippings.txt" to Markdown',
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(
          primary: Colors.teal,
          secondary: Colors.tealAccent,
        ),
      ),
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController _textController = TextEditingController();
  String _fileName = '';
  String _uploadedText = '';
  List<String> _logs = [];
  List<String> _errorLogs = [];

  // Function to pick a file (for web)
  void _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt'],
    );

    if (result != null) {
      PlatformFile file = result.files.first;
      _fileName = file.name;
      setState(() {
        _uploadedText = String.fromCharCodes(file.bytes!);
      });
    }
  }

  void log(String message) {
    _logs.add(message + "\n=====================\n");
    setState(() {});
  }

  void error(String message) {
    _errorLogs.add(message + "\n=====================\n");
    setState(() {});
  }

  String _removeBom(String input) {
    // Check for the UTF-8 BOM and remove it if present
    const bom = '\uFEFF';
    if (input.startsWith(bom)) {
      return input.substring(1);
    }
    return input;
  }

  String _convertToLf(String text) {
    return text.replaceAll('\r\n', '\n'); // Replace CRLF with LF
  }

  // Function to remove quotes that are substrings of others
  List<String> filterSubstringQuotes(Iterable<String> quotes) {
    List<String> filteredQuotes = [];

    for (var quote in quotes) {
      bool isSubstring = false;

      // Check if the current quote is a substring of any already added quote
      for (var existingQuote in filteredQuotes) {
        if (existingQuote.startsWith(quote)) {
          isSubstring = true;
          break;
        } else if (quote.startsWith(existingQuote)) {
          // If the current quote contains the existing one, replace it
          filteredQuotes.remove(existingQuote);
          break;
        }
      }

      if (!isSubstring) {
        filteredQuotes.add(quote);
      }
    }

    return filteredQuotes;
  }

  void _downloadAsZip(Map<String, LinkedHashSet<String>> bookHighlights) {
    // Create a ZIP encoder
    final archive = Archive();

    // Add each markdown file to the archive
    bookHighlights.forEach((bookName, quotesSet) {
      List<String> quotes = filterSubstringQuotes(quotesSet);
      String fileName = "${bookName.replaceAll(RegExp(r'[<>:\"/\\|?*]'), '_')}.md";
      String markdownContent = quotes.map((quote) => "- $quote").join("\n\n");

      // Convert markdown content to bytes and add to the archive
      List<int> contentBytes = Uint8List.fromList(markdownContent.codeUnits);
      archive.addFile(ArchiveFile(fileName, contentBytes.length, contentBytes));
    });

    // Encode the archive to a ZIP format
    List<int> zipBytes = ZipEncoder().encode(archive)!;

    // Create a Blob for the zip file content
    final blob = html.Blob([Uint8List.fromList(zipBytes)], 'application/zip');
    final url = html.Url.createObjectUrlFromBlob(blob);

    // Create an anchor element and trigger the download
    final anchor = html.AnchorElement(href: url)
      ..setAttribute("download", "highlights.zip")
      ..click();

    // Clean up the object URL
    html.Url.revokeObjectUrl(url);

    log("ZIP file created: highlights.zip");
  }

  // Function to parse text (to be implemented with custom parsing rules)
  void _parseInput() {
    _logs.clear();
    _errorLogs.clear();
    // Input text from either the text box or the uploaded file
    String inputText = _textController.text.isNotEmpty
        ? _textController.text
        : _uploadedText;

    inputText = _removeBom(inputText);
    inputText = _convertToLf(inputText);

    if (inputText.isEmpty) {
      error("No input provided for parsing.");
      return;
    }

    // Split the text by the delimiter between highlights
    List<String> highlights = inputText.split("==========");
    int n_highlights = highlights.length - 1;
    log("Total highlights: $n_highlights");

    // A map to store quotes for each book
    Map<String, LinkedHashSet<String>> bookHighlights = {};
    Set<String> books = {};

    for (String highlight in highlights) {
      highlight = _removeBom(highlight).trim();
      // Skip empty lines
      if (highlight.isEmpty) continue;

      // Extract the book name (first part of the highlight)
      final bookNameMatch = RegExp(r'^(.*) \(').firstMatch(highlight);
      if (bookNameMatch == null) {
        error("No book name found in the following highlight:\n$highlight");
        continue;
      }

      String bookName = _removeBom(bookNameMatch.group(1)?.trim() ?? "Unknown Book");
      books.add(bookName);

      // Extract the highlighted quote (the third part)
      final quoteMatch = RegExp(r'Added.*\n+(.*)', multiLine: true).firstMatch(highlight);
      if (quoteMatch == null) {
        error("Could not extract quote in: $highlight");
        continue;
      }

      String highlightedQuote = _removeBom(quoteMatch.group(1)?.trim() ?? "");

      // Add the quote to the corresponding book in the map
      if (!(bookHighlights.containsKey(bookName) && highlightedQuote != "")) {
        bookHighlights[bookName] = new LinkedHashSet<String>();
      }
      bookHighlights[bookName]?.add(highlightedQuote);
    }

    int n_found_books = books.length;
    log("Number of books found: $n_found_books");

    int n_quoted_books = bookHighlights.keys.length;
    log("Number of quoted books: $n_quoted_books");

    // Create markdown files for each book and trigger download
    if (n_quoted_books > 0) {
      _downloadAsZip(bookHighlights);
    } else {
      error("No quoted books captured. Can't generate archive.");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('"My Clippings.txt" to Markdown'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Paste the contents of "My Clippings.txt" or upload it.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            SizedBox(height: 20),
            TextField(
              controller: _textController,
              maxLines: 10,
              style: TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Paste contents of "My Clippings.txt"',
                labelStyle: TextStyle(color: Colors.tealAccent),
                hintText: 'Paste here...',
                hintStyle: TextStyle(color: Colors.grey),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.tealAccent),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.tealAccent),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.tealAccent, width: 2.0),
                ),
              ),
            ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton.icon(
                  onPressed: _pickFile,
                  icon: Icon(Icons.upload_file),
                  label: Text('Upload "My Clippings.txt"'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondary, // Button color
                    foregroundColor: Colors.black, // Text color
                  ),
                ),
                SizedBox(width: 10),
                ElevatedButton.icon(
                  onPressed: _parseInput,
                  icon: Icon(Icons.play_arrow),
                  label: Text('Convert'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.secondary,
                    foregroundColor: Colors.black,
                  ),
                ),
              ],
            ),
            SizedBox(height: 10),
            if (_fileName.isNotEmpty)
              Text(
                'Selected file: $_fileName',
                style: TextStyle(color: Colors.grey),
              ),
            SizedBox(height: 16),

            // Display error logs if there are any
            if (_errorLogs.isNotEmpty) ...[
              Text(
                "Error Logs:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _errorLogs.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Text(
                        _errorLogs[index],
                        style: TextStyle(color: Colors.red),
                      ),
                    );
                  },
                ),
              ),
            ],

            SizedBox(height: 16),

            // Display error logs if there are any
            if (_logs.isNotEmpty) ...[
              Text(
                "Logs:",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _logs.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Text(
                        _logs[index],
                        style: TextStyle(color: Colors.teal),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

