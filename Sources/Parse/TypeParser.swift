//
//  TypeParser.swift
//  Trill
//

import Foundation

extension Parser {
  /// Type Declaration
  ///
  /// type-decl ::= type <typename> {
  ///   [<field-decl> | <func-decl>]*
  /// }
  func parseTypeDecl(_ modifiers: [DeclModifier]) throws -> ASTNode {
    try consume(.type)
    let startLoc = sourceLoc
    let name = try parseIdentifier()
    var conformances = [TypeRefExpr]()
    var genericParams = [GenericParamDecl]()

    if peek() == .leftAngle {
      genericParams = try parseGenericParamDecls()
    }
    
    if case .operator(op: .assign) = peek() {
      consumeToken()
      let bound = try parseType()
      return TypeAliasDecl(name: name,
                           bound: bound,
                           sourceRange: range(start: startLoc))
    }
    if case .colon = peek() {
      consumeToken()
      conformances = try parseSeparated(by: .comma, until: .leftBrace, parseType)
    }
    try consume(.leftBrace)
    var fields = [VarAssignDecl]()
    var methods = [MethodDecl]()
    var staticMethods = [MethodDecl]()
    var subscripts = [SubscriptDecl]()
    var initializers = [InitializerDecl]()
    var deinitializer: DeinitializerDecl?
    let type = DataType(name: name.name)
    loop: while true {
      if case .rightBrace = peek() {
        consumeToken()
        break
      }
      let modifiers = try parseModifiers()
      switch peek() {
      case .poundError, .poundWarning:
        context.add(try parsePoundDiagnosticExpr())
      case .func:
        let decl = try parseFuncDecl(modifiers, forType: type) as! MethodDecl
        if decl.has(attribute: .static) {
          staticMethods.append(decl)
        } else {
          methods.append(decl)
        }
      case .Init:
        initializers.append(try parseFuncDecl(modifiers, forType: type) as! InitializerDecl)
      case .var, .let:
        fields.append(try parseVarAssignDecl(modifiers: modifiers))
      case .subscript:
          subscripts.append(try parseFuncDecl(modifiers, forType: type) as! SubscriptDecl)
      case .deinit:
        if deinitializer != nil {
          throw Diagnostic.error(ParseError.duplicateDeinit, loc: sourceLoc)
        }
        deinitializer = try parseFuncDecl(modifiers, forType:type) as? DeinitializerDecl
      default:
        throw unexpectedToken()
      }
      try consumeAtLeastOneLineSeparator()
    }
    return TypeDecl(name: name, fields: fields,
                    methods: methods,
                    staticMethods: staticMethods,
                    initializers: initializers,
                    subscripts: subscripts,
                    modifiers: modifiers,
                    conformances: conformances,
                    deinit: deinitializer,
                    genericParams: genericParams,
                    sourceRange: range(start: startLoc))
  }
  
  func parseSeparated<T>(by separator: TokenKind, until end: TokenKind, _ parser: () throws -> T) throws -> [T] {
    var values = [T]()
    while peek() != end {
      values.append(try parser())
      if peek() != end {
        try consume(separator)
      }
    }
    return values
  }
  
  func parseType() throws -> TypeRefExpr {
    let startLoc = sourceLoc
    while true {
      switch peek() {
      // HACK
      case .unknown(let char):
        var pointerLevel = 0
        for c in char.characters {
          if c != "*" {
            throw unexpectedToken()
          }
          pointerLevel += 1
        }
        consumeToken()
        return PointerTypeRefExpr(pointedTo: try parseType(),
                                  level: pointerLevel,
                                  sourceRange: range(start: startLoc))
      case .leftParen:
        consumeToken()
        let args = try parseSeparated(by: .comma, until: .rightParen, parseType)
        try consume(.rightParen)
        if case .arrow = peek() {
          consumeToken()
          let ret = try parseType()
          return FuncTypeRefExpr(argNames: args,
                                 retName: ret,
                                 sourceRange: range(start: startLoc))
        } else {
          return TupleTypeRefExpr(fieldNames: args,
                                  sourceRange: range(start: startLoc))
        }
      case .leftBracket:
        consumeToken()
        let innerType = try parseType()
        try consume(.rightBracket)
        return ArrayTypeRefExpr(element: innerType,
                                length: nil,
                                sourceRange: range(start: startLoc))
      case .operator(op: .star):
        consumeToken()
        return PointerTypeRefExpr(pointedTo: try parseType(),
                                  level: 1,
                                  sourceRange: range(start: startLoc))
      case .identifier:
        var id = try parseIdentifier()
        let r = range(start: startLoc)
        id = Identifier(name: id.name, range: r)
        let type = TypeRefExpr(type: DataType(name: id.name),
                               name: id, sourceRange: r)
        guard case .operator(op: .lessThan) = peek() else {
          return type
        }
        let args = try parseGenericParams()
        return GenericTypeRefExpr(unspecializedType: type, args: args)
      default:
        throw unexpectedToken()
      }
    }
  }
  
  func parseProtocolDecl(modifiers: [DeclModifier]) throws -> ProtocolDecl {
    let startLoc = sourceLoc
    try consume(.protocol)
    let name = try parseIdentifier()
    var conformances = [TypeRefExpr]()
    if case .colon = peek() {
      consumeToken()
      guard case .identifier = peek() else {
        throw Diagnostic.error(ParseError.expectedIdentifier(got: peek()),
                               loc: currentToken().range.start,
                               highlights: [
                                 currentToken().range
                               ])
      }
      conformances = try parseSeparated(by: .comma, until: .leftBrace) {
        let name = try parseIdentifier()
        return TypeRefExpr(type: DataType(name: name.name), name: name)
      }
    }
    try consume(.leftBrace)
    var methods = [ProtocolMethodDecl]()
    while true {
      if case .rightBrace = peek() {
        consumeToken()
        break
      }
      let modifiers = try parseModifiers()
      guard case .func = peek()  else {
        throw Diagnostic.error(ParseError.unexpectedExpression(expected: "function"),
                               loc: sourceLoc)
      }
      methods.append(try parseFuncDecl(modifiers,
                                       forType: DataType(name: name.name),
                                       isProtocol: true) as! ProtocolMethodDecl)
    }
    return ProtocolDecl(name: name,
                        fields: [],
                        methods: methods,
                        modifiers: [],
                        conformances: conformances,
                        sourceRange: range(start: startLoc))
  }
}
