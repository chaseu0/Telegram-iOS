#ifndef SweetGramSQLite_h
#define SweetGramSQLite_h

#import <Foundation/Foundation.h>
#import <sqlcipher/sqlite3.h>

/// Thin ObjC wrapper so SweetGramAI Swift code can call sqlite3 without importing SQLite3 module.
@interface SweetGramSQLite : NSObject

+ (int)openDatabase:(NSString *)path db:(sqlite3 **)db;
+ (int)exec:(sqlite3 *)db sql:(const char *)sql;
+ (int)prepare:(sqlite3 *)db sql:(const char *)sql stmt:(sqlite3_stmt **)stmt;
+ (int)step:(sqlite3_stmt *)stmt;
+ (int)finalize:(sqlite3_stmt *)stmt;
+ (sqlite3_int64)lastInsertRowid:(sqlite3 *)db;

+ (int)bindInt64:(sqlite3_stmt *)stmt index:(int)index value:(sqlite3_int64)value;
+ (int)bindInt:(sqlite3_stmt *)stmt index:(int)index value:(int)value;
+ (int)bindDouble:(sqlite3_stmt *)stmt index:(int)index value:(double)value;
+ (int)bindText:(sqlite3_stmt *)stmt index:(int)index value:(const char *)value;

+ (sqlite3_int64)columnInt64:(sqlite3_stmt *)stmt index:(int)index;
+ (int)columnInt:(sqlite3_stmt *)stmt index:(int)index;
+ (double)columnDouble:(sqlite3_stmt *)stmt index:(int)index;
+ (const char *)columnText:(sqlite3_stmt *)stmt index:(int)index;

@end

#endif /* SweetGramSQLite_h */
