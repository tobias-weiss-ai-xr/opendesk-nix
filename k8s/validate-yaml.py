#!/usr/bin/env python3
"""
OpenDesk Edu Kubernetes YAML Validator

Validates all YAML files in the k8s directory for:
- Valid YAML syntax
- Special/hidden characters
- Required fields
- Image reference format
"""

import os
import sys
import yaml
import re
from pathlib import Path

# Colors for output
RED = '\033[91m'
GREEN = '\033[92m'
YELLOW = '\033[93m'
BLUE = '\033[94m'
RESET = '\033[0m'


def validate_yaml_file(filepath):
    """Validate a single YAML file."""
    issues = []
    
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        
        # Check for hidden/non-ASCII characters
        for i, line in enumerate(content.split('\n'), 1):
            if re.search(r'[^\x00-\x7F]', line):
                issues.append(f"Line {i}: Contains non-ASCII characters")
        
        # Try to parse YAML
        try:
            docs = list(yaml.safe_load_all(content))
            if not docs or all(d is None for d in docs):
                issues.append("No valid YAML documents found")
                return [], False
        except yaml.YAMLError as e:
            issues.append(f"Invalid YAML syntax: {e}")
            return issues, False
        
        # Validate each document
        for doc_idx, doc in enumerate(docs):
            if doc is None:
                continue
            
            doc_issues = validate_document(doc, filepath, doc_idx + 1)
            issues.extend(doc_issues)
        
        return issues, len(issues) == 0
        
    except Exception as e:
        issues.append(f"Error reading file: {e}")
        return issues, False


def validate_document(doc, filepath, doc_num):
    """Validate a single YAML document."""
    issues = []
    
    # Check for kind
    if 'kind' not in doc:
        issues.append(f"Doc {doc_num}: Missing 'kind' field")
        return issues
    
    kind = doc['kind']
    metadata = doc.get('metadata', {})
    
    # Check for metadata.name
    if 'name' not in metadata:
        issues.append(f"Doc {doc_num}: Missing 'metadata.name' for {kind}")
    
    # Kind-specific validations
    if kind in ['Deployment', 'StatefulSet']:
        issues.extend(validate_workload(doc, filepath, doc_num, kind))
    elif kind == 'Service':
        issues.extend(validate_service(doc, filepath, doc_num))
    elif kind == 'PersistentVolumeClaim':
        issues.extend(validate_pvc(doc, filepath, doc_num))
    elif kind == 'Ingress':
        issues.extend(validate_ingress(doc, filepath, doc_num))
    elif kind == 'Job':
        issues.extend(validate_job(doc, filepath, doc_num))
    elif kind == 'Secret':
        issues.extend(validate_secret(doc, filepath, doc_num))
    elif kind == 'ConfigMap':
        pass  # ConfigMaps are simple
    
    return issues


def validate_workload(doc, filepath, doc_num, kind):
    """Validate Deployment or StatefulSet."""
    issues = []
    
    spec = doc.get('spec', {})
    template = spec.get('template', {})
    pod_spec = template.get('spec', {})
    
    # Check for containers
    containers = pod_spec.get('containers', [])
    if not containers:
        issues.append(f"Doc {doc_num}: {kind} has no containers")
        return issues
    
    # Validate each container
    for container in containers:
        if 'image' not in container:
            issues.append(f"Doc {doc_num}: Container missing 'image' field")
        elif 'imagePullSecrets' in pod_spec or 'imagePullPolicy' in container:
            # Check image format
            image = container['image']
            if not re.match(r'^[a-z0-9\-\.]+/[a-z0-9\-\.]+/[a-z0-9\-\.]+:.*', image):
                issues.append(f"Doc {doc_num}: Image format may be incorrect: {image[:50]}...")
        
        # Check for resources
        if 'resources' not in container:
            issues.append(f"Doc {doc_num}: Container missing 'resources' (recommended)")
        
        # Check for security context
        security_context = container.get('securityContext', {})
        if 'runAsUser' not in security_context:
            issues.append(f"Doc {doc_num}: Container missing 'runAsUser' in securityContext (recommended)")
        
    # Check for service account
    if 'serviceAccountName' not in pod_spec:
        issues.append(f"Doc {doc_num}: Missing 'serviceAccountName' (recommended)")
    
    # Check for probes
    for container in containers:
        if 'livenessProbe' not in container:
            issues.append(f"Doc {doc_num}: Container missing 'livenessProbe' (recommended)")
        if 'readinessProbe' not in container:
            issues.append(f"Doc {doc_num}: Container missing 'readinessProbe' (recommended)")
    
    return issues


def validate_service(doc, filepath, doc_num):
    """Validate Service."""
    issues = []
    spec = doc.get('spec', {})
    
    if 'selector' not in spec:
        issues.append(f"Doc {doc_num}: Service missing 'selector'")
    if 'ports' not in spec:
        issues.append(f"Doc {doc_num}: Service missing 'ports'")
    
    return issues


def validate_pvc(doc, filepath, doc_num):
    """Validate PersistentVolumeClaim."""
    issues = []
    spec = doc.get('spec', {})
    
    if 'accessModes' not in spec:
        issues.append(f"Doc {doc_num}: PVC missing 'accessModes'")
    if 'resources' not in spec:
        issues.append(f"Doc {doc_num}: PVC missing 'resources'")
    elif 'storage' not in spec.get('resources', {}).get('requests', {}):
        issues.append(f"Doc {doc_num}: PVC missing 'storage' in requests")
    
    return issues


def validate_ingress(doc, filepath, doc_num):
    """Validate Ingress."""
    issues = []
    spec = doc.get('spec', {})
    
    if 'rules' not in spec:
        issues.append(f"Doc {doc_num}: Ingress missing 'rules'")
    if 'tls' in spec and not spec.get('tls'):
        issues.append(f"Doc {doc_num}: Ingress has empty 'tls' section")
    
    return issues


def validate_job(doc, filepath, doc_num):
    """Validate Job."""
    issues = []
    spec = doc.get('spec', {})
    
    if 'template' not in spec:
        issues.append(f"Doc {doc_num}: Job missing 'template'")
    
    return issues


def validate_secret(doc, filepath, doc_num):
    """Validate Secret."""
    issues = []
    
    if 'stringData' not in doc and 'data' not in doc:
        issues.append(f"Doc {doc_num}: Secret has no 'stringData' or 'data'")
    
    # Check for CHANGE_ME in templates
    string_data = doc.get('stringData', {})
    for key, value in string_data.items():
        if 'CHANGE_ME' in value:
            issues.append(f"Doc {doc_num}: Secret value for '{key}' contains 'CHANGE_ME' placeholder")
    
    return issues


def scan_directory(directory):
    """Scan a directory for YAML files and validate them."""
    yaml_files = []
    
    for root, dirs, files in os.walk(directory):
        # Skip hidden directories and common non-k8s directories
        dirs[:] = [d for d in dirs if not d.startswith('.') and d not in ['.git', 'node_modules']]
        
        for file in files:
            if file.endswith('.yaml') or file.endswith('.yml'):
                yaml_files.append(os.path.join(root, file))
    
    return sorted(yaml_files)


def print_results(results):
    """Print validation results."""
    total_files = len(results)
    valid_files = sum(1 for r in results.values() if r['valid'])
    invalid_files = total_files - valid_files
    
    print(f"\n{'='*80}")
    print(f"{BLUE}VALIDATION SUMMARY{RESET}")
    print(f"{'='*80}")
    print(f"Total files scanned: {total_files}")
    print(f"{GREEN}Valid: {valid_files}{RESET}")
    print(f"{RED}Invalid: {invalid_files}{RESET}")
    print(f"{'='*80}\n")
    
    # Print details for invalid files
    if invalid_files > 0:
        print(f"{RED}FILES WITH ISSUES:{RESET}\n")
        for filepath, result in results.items():
            if not result['valid']:
                print(f"\n{YELLOW}📄 {filepath}{RESET}")
                for issue in result['issues']:
                    print(f"  {RED}✗ {issue}{RESET}")
    else:
        print(f"{GREEN}✅ All files are valid!{RESET}\n")
    
    # Print warnings
    has_warnings = any(r['warnings'] for r in results.values())
    if has_warnings:
        print(f"\n{YELLOW}WARNINGS:{RESET}\n")
        for filepath, result in results.items():
            if result['warnings']:
                print(f"\n📄 {filepath}")
                for warning in result['warnings']:
                    print(f"  ⚠️  {warning}")
    
    return invalid_files == 0


def main():
    """Main entry point."""
    if len(sys.argv) > 1:
        target_dir = sys.argv[1]
    else:
        # Default to current directory
        target_dir = '.'
    
    print(f"{BLUE}Scanning for YAML files in: {target_dir}{RESET}\n")
    
    yaml_files = scan_directory(target_dir)
    print(f"Found {len(yaml_files)} YAML files to validate\n")
    
    results = {}
    for filepath in yaml_files:
        issues, is_valid = validate_yaml_file(filepath)
        
        # Separate warnings from errors
        warnings = [i for i in issues if 'recommended' in i.lower() or 'missing' in i.lower()]
        errors = [i for i in issues if i not in warnings]
        
        results[filepath] = {
            'valid': len(errors) == 0,
            'issues': errors,
            'warnings': warnings
        }
        
        # Print progress
        status = f"{GREEN}✅{RESET}" if len(errors) == 0 else f"{RED}❌{RESET}"
        print(f"{status} {filepath} ({len(errors)} errors, {len(warnings)} warnings)")
    
    # Print summary
    all_valid = print_results(results)
    
    return 0 if all_valid else 1


if __name__ == '__main__':
    sys.exit(main())
