#include <iostream>
#include <fstream>
#include <string>
#include <sstream>
#include <vector>
#include <unordered_set>
#include <filesystem>
#include <algorithm>
#include <ctime>
#include <iomanip>
#include <openssl/evp.h>
#include <sys/stat.h>
#include <unistd.h>
#include <dirent.h>

namespace fs = std::filesystem;

// Configuration constants
const std::string SCAN_DIRECTORIES[] = {"/bin", "/sbin", "/usr/bin", "/usr/sbin", "/usr/local/bin", "/tmp", "/var/www"};
const std::vector<std::string> MALICIOUS_PATTERNS = {
    "eval(", "base64_decode(", "exec(", "system(", "passthru(", "shell_exec(",
    "php_uname(", "chmod(", "wget ", "curl ", "nc ", "netcat ", "/dev/tcp/",
    "perl -e", "python -c", "sh -i", "bash -i", "rm -rf", "mkfifo ",
    "\/bin\/sh", "\/bin\/bash", "malicious", "backdoor", "exploit"
};
const size_t MAX_FILE_SIZE = 10485760; // 10MB
const std::string MALWARE_SIGNATURES_DB = "malware_signatures.db";
const std::string LOG_FILE = "/var/log/malware_scanner.log";

// Known malware MD5 hashes
std::unordered_set<std::string> known_malware_hashes = {
    "d41d8cd98f00b204e9800998ecf8427e", // Example hash (replace with real ones)
};

// File types to scan
std::unordered_set<std::string> SCAN_FILE_TYPES = {
    ".php", ".sh", ".py", ".pl", ".js", ".cgi", ".so", ".bin", ""
};

// Logging function
void log_event(const std::string& message) {
    std::ofstream logfile(LOG_FILE, std::ios_base::app);
    if (logfile.is_open()) {
        auto t = std::time(nullptr);
        auto tm = *std::localtime(&t);
        logfile << std::put_time(&tm, "%Y-%m-%d %H:%M:%S") << " - " << message << std::endl;
        logfile.close();
    }
}

// Calculate MD5 hash of a file using EVP API (non-deprecated)
std::string calculate_md5(const std::string& filepath) {
    std::ifstream file(filepath, std::ifstream::binary);
    if (!file) {
        return "";
    }

    EVP_MD_CTX* ctx = EVP_MD_CTX_new();
    if (!ctx) return "";
    EVP_DigestInit_ex(ctx, EVP_md5(), nullptr);

    char buffer[1024];
    while (file.read(buffer, sizeof(buffer))) {
        EVP_DigestUpdate(ctx, buffer, file.gcount());
    }
    EVP_DigestUpdate(ctx, buffer, file.gcount());

    unsigned char result[EVP_MAX_MD_SIZE];
    unsigned int md_len = 0;
    EVP_DigestFinal_ex(ctx, result, &md_len);
    EVP_MD_CTX_free(ctx);

    file.close();

    std::stringstream md5string;
    md5string << std::hex << std::setfill('0');
    for (unsigned int i = 0; i < md_len; i++) {
        md5string << std::setw(2) << (int)result[i];
    }

    return md5string.str();
}

// Check if file has executable permissions
bool is_executable(const std::string& filepath) {
    struct stat st;
    if (stat(filepath.c_str(), &st) != 0) {
        return false;
    }
    return (st.st_mode & S_IXUSR) || (st.st_mode & S_IXGRP) || (st.st_mode & S_IXOTH);
}

// Check for suspicious file names
bool is_suspicious_filename(const std::string& filename) {
    std::vector<std::string> suspicious_patterns = {
        "hack", "exploit", "backdoor", "rootkit", "malware", "virus",
        "trojan", "spyware", "worm", "keylogger", "ransom", "miner"
    };

    std::string lower_filename = filename;
    std::transform(lower_filename.begin(), lower_filename.end(), lower_filename.begin(), ::tolower);

    for (const auto& pattern : suspicious_patterns) {
        if (lower_filename.find(pattern) != std::string::npos) {
            return true;
        }
    }

    return false;
}

// Scan file for malicious patterns
bool scan_file_content(const std::string& filepath) {
    std::ifstream file(filepath);
    if (!file.is_open()) {
        return false;
    }

    std::string line;
    size_t line_number = 0;

    while (std::getline(file, line)) {
        line_number++;
        std::string lower_line = line;
        std::transform(lower_line.begin(), lower_line.end(), lower_line.begin(), ::tolower);

        for (const auto& pattern : MALICIOUS_PATTERNS) {
            if (lower_line.find(pattern) != std::string::npos) {
                log_event("Suspicious pattern found in " + filepath + " at line " + 
                         std::to_string(line_number) + ": " + pattern);
                return true;
            }
        }
    }

    file.close();
    return false;
}

// Load malware signatures from database
void load_malware_signatures() {
    std::ifstream db(MALWARE_SIGNATURES_DB);
    if (db.is_open()) {
        std::string hash;
        while (std::getline(db, hash)) {
            if (hash.length() == 32) { // MD5 hash length
                known_malware_hashes.insert(hash);
            }
        }
        db.close();
    }
}

// Scan a single file
void scan_file(const fs::path& filepath) {
    try {
        // Skip directories and special files
        if (!fs::is_regular_file(filepath)) {
            return;
        }

        // Skip large files
        if (fs::file_size(filepath) > MAX_FILE_SIZE) {
            return;
        }

        // Check file extension
        std::string extension = filepath.extension();
        if (SCAN_FILE_TYPES.find(extension) == SCAN_FILE_TYPES.end()) {
            return;
        }

        std::string path_str = filepath.string();

        // Check for suspicious file names
        if (is_suspicious_filename(filepath.filename())) {
            log_event("Suspicious filename detected: " + path_str);
        }

        // Check executable permissions
        if (is_executable(path_str)) {
            log_event("Executable file detected: " + path_str);
        }

        // Calculate and check MD5 hash
        std::string md5_hash = calculate_md5(path_str);
        if (known_malware_hashes.find(md5_hash) != known_malware_hashes.end()) {
            log_event("Known malware detected: " + path_str + " (MD5: " + md5_hash + ")");
        }

        // Scan file content for malicious patterns
        if (scan_file_content(path_str)) {
            log_event("Malicious content detected in file: " + path_str);
        }
    } catch (const std::exception& e) {
        log_event("Error scanning file " + filepath.string() + ": " + e.what());
    }
}

// Recursive directory scanning
void scan_directory(const std::string& directory) {
    try {
        for (const auto& entry : fs::recursive_directory_iterator(directory)) {
            scan_file(entry.path());
        }
    } catch (const std::exception& e) {
        log_event("Error scanning directory " + directory + ": " + e.what());
    }
}

int main() {
    // Check if running as root
    if (geteuid() != 0) {
        std::cerr << "This program should be run as root for complete system scanning." << std::endl;
        return 1;
    }

    log_event("Malware scanner started");

    // Load malware signatures
    load_malware_signatures();

    // Scan configured directories
    for (const auto& dir : SCAN_DIRECTORIES) {
        if (fs::exists(dir) && fs::is_directory(dir)) {
            log_event("Scanning directory: " + dir);
            scan_directory(dir);
        }
    }

    log_event("Malware scanner completed");
    return 0;
}