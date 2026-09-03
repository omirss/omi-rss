import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Puppeteer service for JavaScript-heavy sites
class PuppeteerService {
  final Dio _dio;
  Process? _serverProcess;
  String? _serverUrl;
  bool _isRunning = false;
  
  PuppeteerService({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }
  
  /// Start puppeteer server
  Future<void> start() async {
    if (_isRunning) return;
    
    try {
      // Check if server is already running
      if (await _checkServerHealth()) {
        _isRunning = true;
        return;
      }
      
      // Get app directory
      final appDir = await getApplicationDocumentsDirectory();
      final puppeteerDir = Directory(p.join(appDir.path, 'puppeteer'));
      
      // Ensure directory exists
      if (!await puppeteerDir.exists()) {
        await puppeteerDir.create(recursive: true);
      }
      
      // Check if puppeteer is installed
      final packageJsonFile = File(p.join(puppeteerDir.path, 'package.json'));
      if (!await packageJsonFile.exists()) {
        await _setupPuppeteer(puppeteerDir);
      }
      
      // Start server
      _serverProcess = await Process.start(
        'node',
        ['server.js'],
        workingDirectory: puppeteerDir.path,
        environment: {
          'PORT': '9222',
          'PUPPETEER_SKIP_CHROMIUM_DOWNLOAD': 'false',
        },
      );
      
      // Listen for server output
      _serverProcess!.stdout.transform(utf8.decoder).listen((data) {
        print('Puppeteer: $data');
        if (data.contains('Server running on')) {
          _serverUrl = 'http://localhost:9222';
          _isRunning = true;
        }
      });
      
      _serverProcess!.stderr.transform(utf8.decoder).listen((data) {
        print('Puppeteer Error: $data');
      });
      
      // Wait for server to start
      await Future.delayed(const Duration(seconds: 5));
      
      // Verify server is running
      if (!await _checkServerHealth()) {
        throw Exception('Failed to start puppeteer server');
      }
      
      _isRunning = true;
    } catch (e) {
      print('Failed to start puppeteer: $e');
      rethrow;
    }
  }
  
  /// Stop puppeteer server
  Future<void> stop() async {
    if (!_isRunning) return;
    
    try {
      _serverProcess?.kill();
      _serverProcess = null;
      _serverUrl = null;
      _isRunning = false;
    } catch (e) {
      print('Failed to stop puppeteer: $e');
    }
  }
  
  /// Fetch page with JavaScript rendering
  Future<String> fetchPage(
    String url, {
    Duration? waitFor,
    String? waitForSelector,
    Map<String, String>? headers,
    bool screenshot = false,
  }) async {
    if (!_isRunning) {
      await start();
    }
    
    try {
      final response = await _dio.post(
        '$_serverUrl/fetch',
        data: {
          'url': url,
          'waitFor': waitFor?.inMilliseconds,
          'waitForSelector': waitForSelector,
          'headers': headers,
          'screenshot': screenshot,
        },
      );
      
      if (response.statusCode == 200) {
        return response.data['html'] as String;
      } else {
        throw Exception('Failed to fetch page: ${response.data['error']}');
      }
    } catch (e) {
      print('Puppeteer fetch error: $e');
      rethrow;
    }
  }
  
  /// Take screenshot of page
  Future<List<int>> screenshot(
    String url, {
    int? width,
    int? height,
    bool fullPage = false,
  }) async {
    if (!_isRunning) {
      await start();
    }
    
    try {
      final response = await _dio.post(
        '$_serverUrl/screenshot',
        data: {
          'url': url,
          'width': width,
          'height': height,
          'fullPage': fullPage,
        },
        options: Options(
          responseType: ResponseType.bytes,
        ),
      );
      
      if (response.statusCode == 200) {
        return response.data as List<int>;
      } else {
        throw Exception('Failed to take screenshot');
      }
    } catch (e) {
      print('Puppeteer screenshot error: $e');
      rethrow;
    }
  }
  
  /// Execute JavaScript on page
  Future<dynamic> executeScript(
    String url,
    String script, {
    Duration? waitFor,
  }) async {
    if (!_isRunning) {
      await start();
    }
    
    try {
      final response = await _dio.post(
        '$_serverUrl/execute',
        data: {
          'url': url,
          'script': script,
          'waitFor': waitFor?.inMilliseconds,
        },
      );
      
      if (response.statusCode == 200) {
        return response.data['result'];
      } else {
        throw Exception('Failed to execute script: ${response.data['error']}');
      }
    } catch (e) {
      print('Puppeteer execute error: $e');
      rethrow;
    }
  }
  
  /// Check server health
  Future<bool> _checkServerHealth() async {
    if (_serverUrl == null) return false;
    
    try {
      final response = await _dio.get('$_serverUrl/health');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
  
  /// Setup puppeteer
  Future<void> _setupPuppeteer(Directory dir) async {
    // Create package.json
    final packageJson = {
      'name': 'rss-reader-puppeteer',
      'version': '1.0.0',
      'dependencies': {
        'puppeteer': '^21.0.0',
        'express': '^4.18.0',
        'body-parser': '^1.20.0',
        'cors': '^2.8.5',
      },
    };
    
    final packageJsonFile = File(p.join(dir.path, 'package.json'));
    await packageJsonFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(packageJson),
    );
    
    // Create server.js
    final serverJs = '''
const express = require('express');
const puppeteer = require('puppeteer');
const bodyParser = require('body-parser');
const cors = require('cors');

const app = express();
const port = process.env.PORT || 9222;

app.use(cors());
app.use(bodyParser.json({ limit: '10mb' }));
app.use(bodyParser.urlencoded({ extended: true, limit: '10mb' }));

let browser;

// Initialize browser
async function initBrowser() {
  if (!browser) {
    browser = await puppeteer.launch({
      headless: 'new',
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-accelerated-2d-canvas',
        '--no-first-run',
        '--no-zygote',
        '--single-process',
        '--disable-gpu',
      ],
    });
  }
  return browser;
}

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Fetch page
app.post('/fetch', async (req, res) => {
  const { url, waitFor, waitForSelector, headers, screenshot } = req.body;
  
  try {
    const browser = await initBrowser();
    const page = await browser.newPage();
    
    // Set viewport
    await page.setViewport({ width: 1920, height: 1080 });
    
    // Set headers if provided
    if (headers) {
      await page.setExtraHTTPHeaders(headers);
    }
    
    // Navigate to page
    await page.goto(url, { waitUntil: 'networkidle2' });
    
    // Wait for selector or timeout
    if (waitForSelector) {
      await page.waitForSelector(waitForSelector, { timeout: 30000 });
    } else if (waitFor) {
      await page.waitForTimeout(waitFor);
    }
    
    // Get HTML
    const html = await page.content();
    
    // Take screenshot if requested
    let screenshotData;
    if (screenshot) {
      screenshotData = await page.screenshot({ encoding: 'base64' });
    }
    
    await page.close();
    
    res.json({ html, screenshot: screenshotData });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Take screenshot
app.post('/screenshot', async (req, res) => {
  const { url, width, height, fullPage } = req.body;
  
  try {
    const browser = await initBrowser();
    const page = await browser.newPage();
    
    // Set viewport
    await page.setViewport({ 
      width: width || 1920, 
      height: height || 1080 
    });
    
    // Navigate to page
    await page.goto(url, { waitUntil: 'networkidle2' });
    
    // Take screenshot
    const screenshot = await page.screenshot({
      fullPage: fullPage || false,
      type: 'png',
    });
    
    await page.close();
    
    res.type('image/png').send(screenshot);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Execute script
app.post('/execute', async (req, res) => {
  const { url, script, waitFor } = req.body;
  
  try {
    const browser = await initBrowser();
    const page = await browser.newPage();
    
    // Navigate to page
    await page.goto(url, { waitUntil: 'networkidle2' });
    
    // Wait if specified
    if (waitFor) {
      await page.waitForTimeout(waitFor);
    }
    
    // Execute script
    const result = await page.evaluate(script);
    
    await page.close();
    
    res.json({ result });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Start server
app.listen(port, () => {
  console.log(`Server running on http://localhost:\${port}`);
});

// Cleanup on exit
process.on('SIGINT', async () => {
  if (browser) {
    await browser.close();
  }
  process.exit();
});
''';
    
    final serverJsFile = File(p.join(dir.path, 'server.js'));
    await serverJsFile.writeAsString(serverJs);
    
    // Install dependencies
    final result = await Process.run(
      'npm',
      ['install'],
      workingDirectory: dir.path,
    );
    
    if (result.exitCode != 0) {
      throw Exception('Failed to install puppeteer dependencies: ${result.stderr}');
    }
  }
  
  /// Dispose
  void dispose() {
    stop();
  }
}