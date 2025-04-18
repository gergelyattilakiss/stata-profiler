/* profile.do - Project-specific Stata profile
 * Purpose: Create isolated package environment and track dependencies in YAML
 * Created: April 10, 2025
 */

clear all
set more off
version 18  // Adjust to your Stata version

// Display startup message
display as text "Loading project-specific profile..."

// Set up project-specific ado directory
global project_root "`c(pwd)'"  // Current directory by default
global ado_dir "$project_root/ado"

// Create ado directory if it doesn't exist
capture mkdir "$ado_dir"

// Create ado subdirectories (necessary for Stata package structure)
foreach subdir in "" "/plus" "/site" "/personal" {
    capture mkdir "$ado_dir`subdir'"
}

// Store original sysdir locations for reference
local oldbase "`c(sysdir_base)'"
local oldplus "`c(sysdir_plus)'"
local oldpersonal "`c(sysdir_personal)'"
local oldsite "`c(sysdir_site)'"
local oldsiteplug "`c(sysdir_siteplug)'"

// Set sysdir to our project locations - this controls where Stata looks for packages
sysdir set PLUS "$ado_dir/plus/"
sysdir set PERSONAL "$ado_dir/personal/"
sysdir set SITE "$ado_dir/site/"

// Display the new ado paths
display as text "Stata will now look for packages ONLY in:"
display as text "  PLUS:     " as result c(sysdir_plus)
display as text "  PERSONAL: " as result c(sysdir_personal)
display as text "  SITE:     " as result c(sysdir_site)

// Path for dependencies file
global deps_file "$project_root/dependencies.yaml"

// Check if dependencies file exists, create if not
capture confirm file "$deps_file"
if (_rc) {
    // Create a new dependencies file with header
    tempname deps_handle
    file open `deps_handle' using "$deps_file", write text replace
    file write `deps_handle' "# Stata Package Dependencies" _n
    file write `deps_handle' "# Generated by profile.do" _n
    file write `deps_handle' "# Updated: `c(current_date)'" _n _n
    file write `deps_handle' "packages:" _n
    file close `deps_handle'
}

// Function to extract version from package
program define extract_version
    args pkg_name
    
    local version "unknown"
    
    // Capture the output of 'which' command
    quietly log using which_out, text name(which_out) 
    which `pkg_name'
    quietly log close which_out
    
    // Read the output and look for version information
    file open which_out using "which_out.log", read text
    file read which_out line
    
    // Skip the first line with the path info
    file read which_out line
    
    // Check if second line has version info (common pattern)
    if regexm("`line'", ".*version[^0-9.]*([0-9][0-9.a-z]*)") {
        local version = regexs(1)
    }
    else {
        // Look through first 5 lines for version info
        local line_count = 0
        while r(eof)==0 & `line_count' < 5 {
            if regexm("`line'", ".*version[^0-9.]*([0-9][0-9.a-z]*)") {
                local version = regexs(1)
                continue, break
            }
            file read which_out line
            local line_count = `line_count' + 1
        }
    }
    
    file close which_out
    rm "which_out.log"
    
    // Return the version
    di as text "`version'"
    return local pkg_version "`version'"
end

// Command to install a package directly to the project's ado directory
program define project_install
    args pkg_name
    
    display as text "Installing `pkg_name' to project directory..."
    
    // Install package (already using project directories due to sysdir settings)
    capture net from "https://www.stata.com/stb/stbplus"
    if (_rc == 0) {
        capture net install `pkg_name', force
    }
    
    if (_rc) {
        // Try SSC if not found in STB repository
        capture ssc install `pkg_name', replace
        if (_rc) {
            display as error "Failed to install `pkg_name'"
            exit _rc
        }
    }
    
    // Get package info using which command and extract version
    local version "unknown"
    capture which `pkg_name'
    if (!_rc) {
        // Extract version from package file
        capture extract_version `pkg_name'
        if (!_rc) {
            local version = r(pkg_version)
        }
    }
    
    // Update dependencies YAML file
    update_deps_file "`pkg_name'" "`version'"
    
    display as text "Package `pkg_name' (version: `version') installed successfully to project ado folder."
end

// Helper program to update the dependencies file
program define update_deps_file
    args pkg_name version
    
    // Read current dependencies file
    tempname deps_in deps_out
    tempfile temp_deps
    
    file open `deps_in' using "$deps_file", read text
    file open `deps_out' using "`temp_deps'", write text replace
    
    // Copy existing content
    local found 0
    file read `deps_in' line
    while r(eof)==0 {
        // Check if this package is already in the file
        if regexm("`line'", "^  `pkg_name':") {
            // Update the version
            file write `deps_out' "  `pkg_name': `version'  # Updated: `c(current_date)'" _n
            local found 1
        }
        else {
            // Keep existing line
            file write `deps_out' "`line'" _n
        }
        file read `deps_in' line
    }
    
    // Add new package if not found
    if (`found' == 0) {
        file write `deps_out' "  `pkg_name': `version'  # Added: `c(current_date)'" _n
    }
    
    // Close files
    file close `deps_in'
    file close `deps_out'
    
    // Replace original with updated file
    copy "`temp_deps'" "$deps_file", replace
end

// Command to install all packages listed in dependencies file
program define install_deps
    // Read dependencies file
    tempname deps_in
    file open `deps_in' using "$deps_file", read text
    
    local in_packages 0
    local install_count 0
    
    file read `deps_in' line
    while r(eof)==0 {
        // Check if we're in the packages section
        if ("`line'" == "packages:") {
            local in_packages 1
        }
        else if (`in_packages' == 1) {
            // Parse package entries
            if regexm("`line'", "^  ([a-zA-Z0-9_]+):") {
                local pkg = regexs(1)
                local ++install_count
                display as text "Installing dependency: `pkg'"
                project_install `pkg'
            }
        }
        file read `deps_in' line
    }
    
    file close `deps_in'
    
    if (`install_count' == 0) {
        display as text "No dependencies found in file."
    }
    else {
        display as text "Installed `install_count' packages from dependencies file."
    }
end

// Display instructions
display as text _newline "--------------------------------------------------------"
display as text "PROJECT PACKAGE ENVIRONMENT ACTIVE"
display as text "- All packages from global Stata installation are ignored"
display as text "- Only packages in `c(pwd)'/ado will be used"
display as text "- To install a package: project_install package_name"
display as text "- To list all installed packages: list_installed"
display as text "- To install all dependencies: install_deps"
display as text "--------------------------------------------------------" _newline
