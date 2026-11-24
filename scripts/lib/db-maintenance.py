#!/root/workspaces/tools/acc1-scripts/mcp-servers/code-search/venv/bin/python
"""
Database Maintenance Script
Cleans up old code_chunks (7-day retention) and orphan vec_chunks.

Auto-compaction: if vectors.db exceeds MAX_DB_SIZE_MB, the file is deleted and
recreated automatically by the action-log-indexer PM2 process (runs every 5 min).

CRITICAL: NO VACUUM — VACUUM breaks vec0 blob references, corrupting vector search.
"""

import sqlite3
import os
import sys
from datetime import datetime

DB_PATH = "/root/workspaces/system/tools/scripts/data/vectors.db"
RETENTION_DAYS = 7
MAX_DB_SIZE_MB = 500

# Add sqlite-vec path
sys.path.insert(0, "/root/workspaces/tools/acc1-scripts/mcp-servers/code-search/venv/lib/python3.12/site-packages")


def main():
    print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] DB Maintenance started")

    try:
        # Check if DB exists
        if not os.path.exists(DB_PATH):
            print(f"Database not found: {DB_PATH}")
            return

        # Check DB size BEFORE connecting — delete if over limit
        db_size_mb = os.path.getsize(DB_PATH) / (1024 * 1024)
        if db_size_mb > MAX_DB_SIZE_MB:
            print(f"WARNING: vectors.db is {db_size_mb:.1f}MB (limit {MAX_DB_SIZE_MB}MB)")
            os.remove(DB_PATH)
            print(f"DB exceeded {MAX_DB_SIZE_MB}MB limit. Deleted for auto-rebuild by indexer (runs every 5 min).")
            return

        # Connect to database
        conn = sqlite3.connect(DB_PATH)
        conn.enable_load_extension(True)

        # Load sqlite-vec extension
        try:
            import sqlite_vec
            sqlite_vec.load(conn)
        except Exception as e:
            print(f"Warning: Could not load sqlite-vec extension: {e}")

        cursor = conn.cursor()

        # Get counts before cleanup
        cursor.execute("SELECT COUNT(*) FROM code_chunks")
        chunks_before = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM vec_chunks")
        vec_chunks_before = cursor.fetchone()[0]

        # Delete old code_chunks
        cursor.execute(
            "DELETE FROM code_chunks WHERE created_at < datetime('now', '-7 days')"
        )
        deleted_chunks = cursor.rowcount

        # Find orphan vec_chunks (chunk_id in vec0 maps to code_chunks.id)
        cursor.execute("""
            SELECT chunk_id FROM vec_chunks_rowids
            WHERE chunk_id NOT IN (SELECT id FROM code_chunks)
        """)
        orphan_ids = [row[0] for row in cursor.fetchall()]

        # Delete orphan vec_chunks
        deleted_orphans = 0
        if orphan_ids:
            placeholders = ','.join('?' * len(orphan_ids))
            cursor.execute(f"DELETE FROM vec_chunks WHERE chunk_id IN ({placeholders})", orphan_ids)
            deleted_orphans = cursor.rowcount

        conn.commit()

        # Get counts after cleanup
        cursor.execute("SELECT COUNT(*) FROM code_chunks")
        chunks_after = cursor.fetchone()[0]

        cursor.execute("SELECT COUNT(*) FROM vec_chunks")
        vec_chunks_after = cursor.fetchone()[0]

        conn.close()

        # Print stats
        print(f"  code_chunks: {chunks_before} → {chunks_after} (deleted: {deleted_chunks})")
        print(f"  vec_chunks: {vec_chunks_before} → {vec_chunks_after} (orphans: {deleted_orphans})")

        # Check DB size AFTER cleanup — delete if still over limit
        if os.path.exists(DB_PATH):
            db_size_mb_after = os.path.getsize(DB_PATH) / (1024 * 1024)
            if db_size_mb_after > MAX_DB_SIZE_MB:
                print(f"WARNING: vectors.db is still {db_size_mb_after:.1f}MB after cleanup (limit {MAX_DB_SIZE_MB}MB)")
                os.remove(DB_PATH)
                print(f"DB exceeded {MAX_DB_SIZE_MB}MB limit. Deleted for auto-rebuild by indexer (runs every 5 min).")
                return

        print(f"[{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}] DB Maintenance completed")

    except Exception as e:
        print(f"ERROR: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()
