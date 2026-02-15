<?php
// Simplified bootstrap for server devlog
// Only loads what's needed for Google Sheets logging

require_once(__DIR__ . '/vendor/autoload.php');

// Load all function files
foreach (glob(__DIR__ . '/functions/*.php') as $file) {
    if (substr($file, -4) == '.php') {
        require_once($file);
    }
}
