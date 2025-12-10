import SwiftUI
import WebKit

struct CanvasWebView: UIViewRepresentable {
    @Bindable var viewModel: EditorViewModel
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.javaScriptEnabled = true
        
        let contentController = WKUserContentController()
        contentController.add(context.coordinator, name: "mindCanvas")
        config.userContentController = contentController
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        
        if let htmlURL = Bundle.main.url(forResource: "canvas", withExtension: "html") {
            webView.loadFileURL(htmlURL, allowingReadAccessTo: htmlURL.deletingLastPathComponent())
        } else {
            loadFallbackHTML(webView)
        }
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
    }
    
    private func loadFallbackHTML(_ webView: WKWebView) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                * { margin: 0; padding: 0; box-sizing: border-box; }
                body {
                    width: 100vw;
                    height: 100vh;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
                    background: #f5f5f5;
                }
                .canvas-container {
                    width: 100%;
                    height: 100%;
                    background: white;
                    border-radius: 12px;
                    box-shadow: 0 2px 20px rgba(0,0,0,0.1);
                    display: flex;
                    flex-direction: column;
                    align-items: center;
                    justify-content: center;
                    position: relative;
                    overflow: hidden;
                }
                canvas {
                    position: absolute;
                    top: 0;
                    left: 0;
                    cursor: crosshair;
                }
                .toolbar {
                    position: absolute;
                    top: 20px;
                    left: 20px;
                    background: white;
                    border-radius: 8px;
                    padding: 8px;
                    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
                    display: flex;
                    gap: 8px;
                }
                .tool-btn {
                    width: 40px;
                    height: 40px;
                    border: none;
                    background: #f0f0f0;
                    border-radius: 6px;
                    cursor: pointer;
                    display: flex;
                    align-items: center;
                    justify-content: center;
                    font-size: 18px;
                }
                .tool-btn.active {
                    background: #007AFF;
                    color: white;
                }
                .info {
                    text-align: center;
                    color: #666;
                }
                .info h2 {
                    font-size: 24px;
                    margin-bottom: 12px;
                    color: #333;
                }
            </style>
        </head>
        <body>
            <div class="canvas-container">
                <canvas id="drawingCanvas"></canvas>
                <div class="toolbar">
                    <button class="tool-btn active" id="penBtn" title="画笔">✏️</button>
                    <button class="tool-btn" id="eraserBtn" title="橡皮擦">🧹</button>
                    <button class="tool-btn" id="frameBtn" title="创建框架">🖼️</button>
                    <button class="tool-btn" id="clearBtn" title="清空">🗑️</button>
                </div>
                <div class="info">
                    <h2>简易画布</h2>
                    <p>使用左侧工具栏绘制</p>
                    <p style="margin-top: 8px; font-size: 12px; color: #999;">
                        完整的 tldraw 画布将在后续集成
                    </p>
                </div>
            </div>
            
            <script>
                const canvas = document.getElementById('drawingCanvas');
                const ctx = canvas.getContext('2d');
                let isDrawing = false;
                let currentTool = 'pen';
                let lastX = 0;
                let lastY = 0;
                
                function resizeCanvas() {
                    canvas.width = canvas.parentElement.clientWidth;
                    canvas.height = canvas.parentElement.clientHeight;
                }
                
                resizeCanvas();
                window.addEventListener('resize', resizeCanvas);
                
                canvas.addEventListener('mousedown', (e) => {
                    isDrawing = true;
                    [lastX, lastY] = [e.offsetX, e.offsetY];
                });
                
                canvas.addEventListener('mousemove', (e) => {
                    if (!isDrawing) return;
                    
                    ctx.beginPath();
                    ctx.moveTo(lastX, lastY);
                    ctx.lineTo(e.offsetX, e.offsetY);
                    
                    if (currentTool === 'pen') {
                        ctx.strokeStyle = '#000';
                        ctx.lineWidth = 2;
                    } else if (currentTool === 'eraser') {
                        ctx.strokeStyle = '#fff';
                        ctx.lineWidth = 20;
                    }
                    
                    ctx.lineCap = 'round';
                    ctx.stroke();
                    
                    [lastX, lastY] = [e.offsetX, e.offsetY];
                });
                
                canvas.addEventListener('mouseup', () => {
                    isDrawing = false;
                    notifyCanvasUpdate();
                });
                
                document.getElementById('penBtn').addEventListener('click', () => {
                    currentTool = 'pen';
                    updateToolButtons('penBtn');
                });
                
                document.getElementById('eraserBtn').addEventListener('click', () => {
                    currentTool = 'eraser';
                    updateToolButtons('eraserBtn');
                });
                
                document.getElementById('frameBtn').addEventListener('click', () => {
                    drawFrame();
                });
                
                document.getElementById('clearBtn').addEventListener('click', () => {
                    ctx.clearRect(0, 0, canvas.width, canvas.height);
                    notifyCanvasUpdate();
                });
                
                function updateToolButtons(activeId) {
                    document.querySelectorAll('.tool-btn').forEach(btn => {
                        btn.classList.remove('active');
                    });
                    document.getElementById(activeId).classList.add('active');
                }
                
                function drawFrame() {
                    const x = canvas.width / 2 - 150;
                    const y = canvas.height / 2 - 100;
                    ctx.strokeStyle = '#007AFF';
                    ctx.lineWidth = 3;
                    ctx.strokeRect(x, y, 300, 200);
                    notifyCanvasUpdate();
                }
                
                function notifyCanvasUpdate() {
                    try {
                        const imageData = canvas.toDataURL('image/png');
                        window.webkit.messageHandlers.mindCanvas.postMessage({
                            event: 'canvas_updated',
                            data: imageData
                        });
                    } catch (e) {
                        console.log('Failed to notify:', e);
                    }
                }
                
                function insertImage(url, x, y, width, height) {
                    const img = new Image();
                    img.crossOrigin = 'anonymous';
                    img.onload = () => {
                        ctx.drawImage(img, x || 100, y || 100, width || 200, height || 150);
                        notifyCanvasUpdate();
                    };
                    img.src = url;
                }
                
                window.insertImage = insertImage;
                
                window.webkit.messageHandlers.mindCanvas.postMessage({
                    event: 'canvas_ready'
                });
            </script>
        </body>
        </html>
        """
        
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var viewModel: EditorViewModel
        
        init(viewModel: EditorViewModel) {
            self.viewModel = viewModel
        }
        
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: Any],
                  let event = dict["event"] as? String else {
                return
            }
            
            Task { @MainActor in
                switch event {
                case "canvas_ready":
                    print("画布已就绪")
                    
                case "canvas_updated":
                    if let data = dict["data"] as? String {
                        viewModel.updateCanvasSnapshot(data)
                    }
                    
                case "selection_changed":
                    if let hasSelection = dict["hasSelection"] as? Bool {
                        viewModel.updateSelection(hasSelection: hasSelection)
                    }
                    
                default:
                    break
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("WebView 加载完成")
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("WebView 加载失败: \(error.localizedDescription)")
        }
    }
}

