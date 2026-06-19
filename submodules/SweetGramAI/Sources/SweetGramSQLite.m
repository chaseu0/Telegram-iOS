#import "SweetGramSQLite.h"
#import <Foundation/Foundation.h>

@implementation SweetGramSQLite

+ (int)openDatabase:(NSString *)path db:(sqlite3 **)db {
    return sqlite3_open([path UTF8String], db);
}

+ (int)exec:(sqlite3 *)db sql:(const char *)sql {
    return sqlite3_exec(db, sql, nil, nil, nil);
}

+ (int)prepare:(sqlite3 *)db sql:(const char *)sql stmt:(sqlite3_stmt **)stmt {
    return sqlite3_prepare_v2(db, sql, -1, stmt, nil);
}

+ (int)step:(sqlite3_stmt *)stmt {
    return sqlite3_step(stmt);
}

+ (int)finalize:(sqlite3_stmt *)stmt {
    return sqlite3_finalize(stmt);
}

+ (sqlite3_int64)lastInsertRowid:(sqlite3 *)db {
    return sqlite3_last_insert_rowid(db);
}

+ (int)bindInt64:(sqlite3_stmt *)stmt index:(int)index value:(sqlite3_int64)value {
    return sqlite3_bind_int64(stmt, index, value);
}

+ (int)bindInt:(sqlite3_stmt *)stmt index:(int)index value:(int)value {
    return sqlite3_bind_int(stmt, index, value);
}

+ (int)bindDouble:(sqlite3_stmt *)stmt index:(int)index value:(double)value {
    return sqlite3_bind_double(stmt, index, value);
}

+ (int)bindText:(sqlite3_stmt *)stmt index:(int)index value:(const char *)value {
    return sqlite3_bind_text(stmt, index, value, -1, (void *)0xFFFFFFFF);
}

+ (sqlite3_int64)columnInt64:(sqlite3_stmt *)stmt index:(int)index {
    return sqlite3_column_int64(stmt, index);
}

+ (int)columnInt:(sqlite3_stmt *)stmt index:(int)index {
    return sqlite3_column_int(stmt, index);
}

+ (double)columnDouble:(sqlite3_stmt *)stmt index:(int)index {
    return sqlite3_column_double(stmt, index);
}

+ (const char *)columnText:(sqlite3_stmt *)stmt index:(int)index {
    return (const char *)sqlite3_column_text(stmt, index);
}

@end
