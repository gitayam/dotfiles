#!/bin/bash

# Create an index.html that displays the image/file directly
# Usage: create-index.sh <directory> <filename>

DIR="$1"
FILE="$2"

if [[ -z "$DIR" ]] || [[ -z "$FILE" ]]; then
    exit 0
fi

# Check if it's an image
if [[ "$FILE" =~ \.(png|jpg|jpeg|gif|webp|svg)$ ]]; then
    cat > "$DIR/index.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>$FILE</title>
    <style>
        body {
            margin: 0;
            padding: 20px;
            background: #1a1a1a;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        }
        .container {
            text-align: center;
            max-width: 95vw;
        }
        img {
            max-width: 100%;
            max-height: 90vh;
            box-shadow: 0 10px 40px rgba(0,0,0,0.5);
            border-radius: 8px;
        }
        .filename {
            color: #888;
            margin-top: 20px;
            font-size: 14px;
        }
        .download {
            display: inline-block;
            margin-top: 20px;
            padding: 10px 20px;
            background: #007bff;
            color: white;
            text-decoration: none;
            border-radius: 5px;
        }
        .download:hover {
            background: #0056b3;
        }
    </style>
</head>
<body>
    <div class="container">
        <img src="$FILE" alt="$FILE">
        <div class="filename">$FILE</div>
        <a href="$FILE" download class="download">⬇ Download</a>
    </div>
</body>
</html>
EOF

# Check if it's a video
elif [[ "$FILE" =~ \.(mp4|webm|mov|avi)$ ]]; then
    cat > "$DIR/index.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>$FILE</title>
    <style>
        body {
            margin: 0;
            padding: 20px;
            background: #1a1a1a;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
        }
        .container {
            text-align: center;
            max-width: 95vw;
        }
        video {
            max-width: 100%;
            max-height: 80vh;
            box-shadow: 0 10px 40px rgba(0,0,0,0.5);
            border-radius: 8px;
        }
        .filename {
            color: #888;
            margin-top: 20px;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="container">
        <video controls>
            <source src="$FILE" type="video/${FILE##*.}">
            Your browser does not support the video tag.
        </video>
        <div class="filename">$FILE</div>
    </div>
</body>
</html>
EOF

# Check if it's a PDF
elif [[ "$FILE" =~ \.pdf$ ]]; then
    cat > "$DIR/index.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>$FILE</title>
    <style>
        body {
            margin: 0;
            padding: 0;
            overflow: hidden;
        }
        iframe {
            width: 100vw;
            height: 100vh;
            border: none;
        }
    </style>
</head>
<body>
    <iframe src="$FILE"></iframe>
</body>
</html>
EOF

fi