<#
.SYNOPSIS
    Manual override workflow for environment control with web interface
.DESCRIPTION
    Provides a simple web-based interface for manual control of environment shutdown/startup
    with schedule override capabilities. Can be deployed as an Azure Function.
.PARAMETER Port
    Port to run the web server on (default: 8080)
#>

param(
    [int]$Port = 8080
)

# HTML template for the web interface
$htmlTemplate = @'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Tour Bus Environment Control</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            padding: 20px;
        }
        
        .container {
            background: white;
            border-radius: 20px;
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);
            max-width: 600px;
            width: 100%;
            padding: 40px;
        }
        
        h1 {
            color: #333;
            margin-bottom: 10px;
            font-size: 28px;
        }
        
        .subtitle {
            color: #666;
            margin-bottom: 30px;
            font-size: 14px;
        }
        
        .environment-grid {
            display: grid;
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .environment-card {
            border: 2px solid #e0e0e0;
            border-radius: 12px;
            padding: 20px;
            transition: all 0.3s ease;
        }
        
        .environment-card:hover {
            border-color: #667eea;
            box-shadow: 0 5px 15px rgba(102, 126, 234, 0.1);
        }
        
        .env-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            margin-bottom: 15px;
        }
        
        .env-name {
            font-size: 20px;
            font-weight: 600;
            color: #333;
        }
        
        .env-status {
            padding: 5px 12px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: 600;
            text-transform: uppercase;
        }
        
        .status-running {
            background: #d4edda;
            color: #155724;
        }
        
        .status-stopped {
            background: #f8d7da;
            color: #721c24;
        }
        
        .status-unknown {
            background: #fff3cd;
            color: #856404;
        }
        
        .env-info {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 10px;
            margin-bottom: 20px;
            font-size: 14px;
            color: #666;
        }
        
        .info-item {
            display: flex;
            flex-direction: column;
        }
        
        .info-label {
            font-weight: 600;
            margin-bottom: 2px;
        }
        
        .action-buttons {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 10px;
        }
        
        .btn {
            padding: 12px 20px;
            border: none;
            border-radius: 8px;
            font-size: 14px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s ease;
            text-transform: uppercase;
            letter-spacing: 0.5px;
        }
        
        .btn-start {
            background: #28a745;
            color: white;
        }
        
        .btn-start:hover {
            background: #218838;
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(40, 167, 69, 0.3);
        }
        
        .btn-stop {
            background: #dc3545;
            color: white;
        }
        
        .btn-stop:hover {
            background: #c82333;
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(220, 53, 69, 0.3);
        }
        
        .btn:disabled {
            opacity: 0.5;
            cursor: not-allowed;
            transform: none !important;
        }
        
        .override-section {
            margin-top: 15px;
            padding-top: 15px;
            border-top: 1px solid #e0e0e0;
        }
        
        .checkbox-container {
            display: flex;
            align-items: center;
            gap: 10px;
            font-size: 14px;
            color: #666;
        }
        
        .checkbox-container input[type="checkbox"] {
            width: 18px;
            height: 18px;
            cursor: pointer;
        }
        
        .alert {
            padding: 15px;
            border-radius: 8px;
            margin-bottom: 20px;
            display: none;
        }
        
        .alert-success {
            background: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
        }
        
        .alert-error {
            background: #f8d7da;
            color: #721c24;
            border: 1px solid #f5c6cb;
        }
        
        .loading {
            display: inline-block;
            width: 14px;
            height: 14px;
            border: 2px solid #f3f3f3;
            border-top: 2px solid #667eea;
            border-radius: 50%;
            animation: spin 1s linear infinite;
            margin-left: 10px;
        }
        
        @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
        }
        
        .last-action {
            margin-top: 30px;
            padding: 15px;
            background: #f8f9fa;
            border-radius: 8px;
            font-size: 14px;
            color: #666;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚌 Tour Bus Environment Control</h1>
        <p class="subtitle">Manual override interface for development and QA environments</p>
        
        <div id="alert" class="alert"></div>
        
        <div class="environment-grid">
            <div class="environment-card">
                <div class="env-header">
                    <span class="env-name">Development</span>
                    <span class="env-status status-unknown" id="dev-status">Checking...</span>
                </div>
                <div class="env-info">
                    <div class="info-item">
                        <span class="info-label">Schedule:</span>
                        <span>7 AM - 7 PM EST</span>
                    </div>
                    <div class="info-item">
                        <span class="info-label">Cost Savings:</span>
                        <span>$1,340/month</span>
                    </div>
                </div>
                <div class="action-buttons">
                    <button class="btn btn-start" onclick="controlEnvironment('Development', 'Startup')">
                        Start
                    </button>
                    <button class="btn btn-stop" onclick="controlEnvironment('Development', 'Shutdown')">
                        Stop
                    </button>
                </div>
                <div class="override-section">
                    <div class="checkbox-container">
                        <input type="checkbox" id="dev-override">
                        <label for="dev-override">Override next scheduled action (24 hours)</label>
                    </div>
                </div>
            </div>
            
            <div class="environment-card">
                <div class="env-header">
                    <span class="env-name">QA</span>
                    <span class="env-status status-unknown" id="qa-status">Checking...</span>
                </div>
                <div class="env-info">
                    <div class="info-item">
                        <span class="info-label">Schedule:</span>
                        <span>7 AM - 7 PM EST</span>
                    </div>
                    <div class="info-item">
                        <span class="info-label">Cost Savings:</span>
                        <span>$980/month</span>
                    </div>
                </div>
                <div class="action-buttons">
                    <button class="btn btn-start" onclick="controlEnvironment('QA', 'Startup')">
                        Start
                    </button>
                    <button class="btn btn-stop" onclick="controlEnvironment('QA', 'Shutdown')">
                        Stop
                    </button>
                </div>
                <div class="override-section">
                    <div class="checkbox-container">
                        <input type="checkbox" id="qa-override">
                        <label for="qa-override">Override next scheduled action (24 hours)</label>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="last-action" id="last-action" style="display: none;">
            <strong>Last Action:</strong> <span id="last-action-text"></span>
        </div>
    </div>
    
    <script>
        const API_URL = window.location.origin + '/api';
        
        async function checkEnvironmentStatus() {
            try {
                const response = await fetch(`${API_URL}/status`);
                const data = await response.json();
                
                updateStatus('dev', data.development);
                updateStatus('qa', data.qa);
            } catch (error) {
                console.error('Failed to check status:', error);
            }
        }
        
        function updateStatus(env, status) {
            const element = document.getElementById(`${env}-status`);
            element.textContent = status;
            element.className = `env-status status-${status.toLowerCase()}`;
        }
        
        async function controlEnvironment(environment, action) {
            const override = document.getElementById(`${environment.toLowerCase()}-override`).checked;
            
            showAlert('info', `${action} ${environment} environment...`);
            disableButtons(true);
            
            try {
                const response = await fetch(`${API_URL}/control`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify({
                        environment: environment,
                        action: action,
                        overrideSchedule: override
                    })
                });
                
                const data = await response.json();
                
                if (response.ok) {
                    showAlert('success', `Successfully initiated ${action.toLowerCase()} for ${environment} environment`);
                    updateLastAction(`${action} ${environment} at ${new Date().toLocaleString()}`);
                    
                    // Refresh status after a delay
                    setTimeout(checkEnvironmentStatus, 5000);
                } else {
                    showAlert('error', `Failed to ${action.toLowerCase()} ${environment}: ${data.error}`);
                }
            } catch (error) {
                showAlert('error', `Error: ${error.message}`);
            } finally {
                disableButtons(false);
            }
        }
        
        function showAlert(type, message) {
            const alert = document.getElementById('alert');
            alert.className = `alert alert-${type === 'success' ? 'success' : type === 'error' ? 'error' : 'info'}`;
            alert.textContent = message;
            alert.style.display = 'block';
            
            if (type !== 'info') {
                setTimeout(() => {
                    alert.style.display = 'none';
                }, 5000);
            }
        }
        
        function disableButtons(disabled) {
            document.querySelectorAll('.btn').forEach(button => {
                button.disabled = disabled;
            });
        }
        
        function updateLastAction(text) {
            document.getElementById('last-action').style.display = 'block';
            document.getElementById('last-action-text').textContent = text;
        }
        
        // Check status on page load
        window.addEventListener('load', () => {
            checkEnvironmentStatus();
            // Refresh status every 30 seconds
            setInterval(checkEnvironmentStatus, 30000);
        });
    </script>
</body>
</html>
'@

# Function to handle HTTP requests
function Start-WebServer {
    param([int]$Port)
    
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://+:$Port/")
    
    try {
        $listener.Start()
        Write-Host "Manual override web server started on port $Port" -ForegroundColor Green
        Write-Host "Access the interface at: http://localhost:$Port" -ForegroundColor Cyan
        
        while ($listener.IsListening) {
            $context = $listener.GetContext()
            $request = $context.Request
            $response = $context.Response
            
            switch ($request.Url.LocalPath) {
                "/" {
                    # Serve the HTML interface
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($htmlTemplate)
                    $response.ContentType = "text/html"
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                }
                
                "/api/status" {
                    # Check environment status
                    $status = @{
                        development = "Unknown"
                        qa = "Unknown"
                    }
                    
                    # TODO: Implement actual status checking
                    $jsonResponse = $status | ConvertTo-Json
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonResponse)
                    $response.ContentType = "application/json"
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                }
                
                "/api/control" {
                    if ($request.HttpMethod -eq "POST") {
                        # Read request body
                        $reader = [System.IO.StreamReader]::new($request.InputStream)
                        $body = $reader.ReadToEnd()
                        $data = $body | ConvertFrom-Json
                        
                        # Trigger Logic App webhook
                        $logicAppUrl = $env:LOGIC_APP_MANUAL_TRIGGER_URL
                        if ($logicAppUrl) {
                            try {
                                $result = Invoke-RestMethod `
                                    -Uri $logicAppUrl `
                                    -Method Post `
                                    -Body ($data | ConvertTo-Json) `
                                    -ContentType "application/json"
                                
                                $jsonResponse = @{ success = $true; result = $result } | ConvertTo-Json
                            }
                            catch {
                                $jsonResponse = @{ success = $false; error = $_.Exception.Message } | ConvertTo-Json
                            }
                        }
                        else {
                            $jsonResponse = @{ success = $false; error = "Logic App URL not configured" } | ConvertTo-Json
                        }
                        
                        $buffer = [System.Text.Encoding]::UTF8.GetBytes($jsonResponse)
                        $response.ContentType = "application/json"
                        $response.ContentLength64 = $buffer.Length
                        $response.OutputStream.Write($buffer, 0, $buffer.Length)
                    }
                }
                
                default {
                    $response.StatusCode = 404
                    $buffer = [System.Text.Encoding]::UTF8.GetBytes("Not Found")
                    $response.ContentLength64 = $buffer.Length
                    $response.OutputStream.Write($buffer, 0, $buffer.Length)
                }
            }
            
            $response.Close()
        }
    }
    catch {
        Write-Error "Web server error: $_"
    }
    finally {
        $listener.Stop()
    }
}

# Start the web server
Start-WebServer -Port $Port