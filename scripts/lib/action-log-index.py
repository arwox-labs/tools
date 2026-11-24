#!/usr/bin/env python3
"""
Action Log Indexer - Semantic indexing for agent action logs
Uses code-search MCP embeddings to enable natural language search
"""
import sys
import os
import asyncio
from datetime import datetime
from pathlib import Path

# Add MCP code-search to Python path
MCP_DIR = '/root/workspaces/tools/acc1-scripts/mcp-servers/code-search/'
sys.path.insert(0, MCP_DIR)

# Constants
DB_PATH = '/root/workspaces/system/tools/scripts/data/vectors.db'

# Directories to index
INDEX_DIRS = [
    {'path': '/root/workspaces/system/tools/scripts/pm2/', 'patterns': ['*.sh', '*.py'], 'exclude': ['__pycache__']},
    {'path': '/root/workspaces/system/tools/scripts/schedulers/', 'patterns': ['*.sh'], 'exclude': []},
    # NOTE: /root/claude-projects/ REMOVED — too heavy for 5min scan cycle (caused server overload 2026-02-14)
    # Use mcp__code-search__index_project manually for main project indexing
]

def main():
    """Index action logs using code-search embeddings"""
    start_time = datetime.now()
    print(f"[{start_time.strftime('%Y-%m-%d %H:%M:%S')}] Action log indexer starting")

    try:
        # Import MCP modules (after path is set)
        from embeddings import EmbeddingCascade
        from database import VectorDatabase
        from indexer import CodeIndexer

        # Initialize embedding cascade from environment
        config = {
            'voyage_api_key': os.getenv('VOYAGE_API_KEY'),
            'jina_api_key': os.getenv('JINA_API_KEY'),
            'openai_api_key': os.getenv('OPENAI_API_KEY')
        }

        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Initializing embedder cascade")
        embedder = EmbeddingCascade(config)

        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Opening vector database: {DB_PATH}")
        db = VectorDatabase(DB_PATH)

        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Creating indexer")
        indexer = CodeIndexer(embedder, db)

        # Index multiple directories
        total_indexed = 0
        for dir_config in INDEX_DIRS:
            dir_path = dir_config['path']
            if not os.path.isdir(dir_path):
                print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Skipping (not found): {dir_path}")
                continue

            print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] Indexing: {dir_path}")
            asyncio.run(
                indexer.index_directory(
                    dir_path,
                    patterns=dir_config['patterns'],
                    exclude_patterns=dir_config['exclude']
                )
            )
            total_indexed += 1

        # Get final stats
        end_time = datetime.now()
        duration = (end_time - start_time).total_seconds()

        print(f"[{end_time.strftime('%Y-%m-%d %H:%M:%S')}] Indexing complete")
        print(f"Duration: {duration:.2f}s")
        print(f"Directories indexed: {total_indexed}/{len(INDEX_DIRS)}")

        return 0

    except ImportError as e:
        print(f"ERROR: Failed to import MCP modules: {e}", file=sys.stderr)
        print(f"MCP directory: {MCP_DIR}", file=sys.stderr)
        return 1
    except Exception as e:
        print(f"ERROR: Indexing failed: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        return 1

if __name__ == '__main__':
    sys.exit(main())
