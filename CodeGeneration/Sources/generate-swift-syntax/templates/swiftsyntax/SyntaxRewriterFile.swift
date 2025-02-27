//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2014 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import SwiftSyntax
import SwiftSyntaxBuilder
import SyntaxSupport
import Utils

let syntaxRewriterFile = SourceFileSyntax(leadingTrivia: copyrightHeader) {
  try! ClassDeclSyntax(
    """
    //
    // This file defines the SyntaxRewriter, a class that performs a standard walk
    // and tree-rebuilding pattern.
    //
    // Subclassers of this class can override the walking behavior for any syntax
    // node and transform nodes however they like.
    //
    //===----------------------------------------------------------------------===//

    open class SyntaxRewriter
    """
  ) {
    DeclSyntax("public let viewMode: SyntaxTreeViewMode")
    DeclSyntax(
      """
      /// The raw arena in which the parents of rewritten nodes should be allocated.
      /// 
      /// The `SyntaxRewriter` subclass is responsible for generating the rewritten nodes. To incorporate them into the
      /// tree, all of the rewritten node's parents also need to be re-created. This is the arena in which those 
      /// intermediate raw nodes should be allocated.
      private let rawArena: RawSyntaxArena?
      """
    )

    DeclSyntax(
      """
      public init(viewMode: SyntaxTreeViewMode = .sourceAccurate) {
        self.viewMode = viewMode
        self.rawArena = nil
      }
      """
    )

    DeclSyntax(
      """
      @_spi(RawSyntax)
      public init(viewMode: SyntaxTreeViewMode = .sourceAccurate, rawAllocationArena: RawSyntaxArena? = nil) {
        self.viewMode = viewMode
        self.rawArena = rawAllocationArena
      }
      """
    )

    DeclSyntax(
      """
      /// Rewrite `node`, keeping its parent unless `detach` is `true`.
      public func rewrite(_ node: some SyntaxProtocol, detach: Bool = false) -> Syntax {
        let rewritten = self.visitImpl(Syntax(node))
        if detach {
          return rewritten
        }

        return withExtendedLifetime(rewritten) {
          return Syntax(node).replacingSelf(rewritten.raw, rawNodeArena: rewritten.raw.arenaReference.retained, rawAllocationArena: RawSyntaxArena())
        }
      }
      """
    )

    DeclSyntax(
      """
      /// Visit any Syntax node.
      ///   - Parameter node: the node that is being visited
      ///   - Returns: the rewritten node
      @available(*, deprecated, renamed: "rewrite(_:detach:)")
      public func visit(_ node: Syntax) -> Syntax {
        return visitImpl(node)
      }
      """
    )

    DeclSyntax(
      """
      public func visit<T: SyntaxChildChoices>(_ node: T) -> T {
        visitImpl(Syntax(node)).cast(T.self)
      }
      """
    )

    DeclSyntax(
      """
      /// The function called before visiting the node and its descendants.
      ///   - node: the node we are about to visit.
      open func visitPre(_ node: Syntax) {}
      """
    )

    DeclSyntax(
      """
      /// Override point to choose custom visitation dispatch instead of the
      /// specialized `visit(_:)` methods. Use this instead of those methods if
      /// you intend to dynamically dispatch rewriting behavior.
      /// - note: If this method returns a non-nil result, the subsequent
      ///         `visitAny(_:)` methods and the specialized `visit(_:)`
      ///         methods will not be called for this node and the
      ///         visited node will be replaced by the returned node in the
      ///         rewritten tree.
      ///         You can call the ``SyntaxRewriter/rewrite(_:detach:)``
      ///         method recursively when returning a non-nil result
      ///         if you want to visit the node's children anyway.
      open func visitAny(_ node: Syntax) -> Syntax? {
        return nil
      }
      """
    )

    DeclSyntax(
      """
      /// The function called after visiting the node and its descendants.
      ///   - node: the node we just finished visiting.
      open func visitPost(_ node: Syntax) {}
      """
    )

    DeclSyntax(
      """
      /// Visit a ``TokenSyntax``.
      ///   - Parameter token: the token that is being visited
      ///   - Returns: the rewritten node
      open func visit(_ token: TokenSyntax) -> TokenSyntax {
        return token
      }
      """
    )

    for node in SYNTAX_NODES where !node.kind.isBase {
      if (node.base == .syntax || node.base == .syntaxCollection) && node.kind != .missing {
        DeclSyntax(
          """
          /// Visit a \(raw: node.kind.doccLink).
          ///   - Parameter node: the node that is being visited
          ///   - Returns: the rewritten node
          \(node.apiAttributes())\
          open func visit(_ node: \(node.kind.syntaxType)) -> \(node.kind.syntaxType) {
            return \(node.kind.syntaxType)(unsafeCasting: visitChildren(node._syntaxNode))
          }
          """
        )
      } else {
        DeclSyntax(
          """
          /// Visit a \(raw: node.kind.doccLink).
          ///   - Parameter node: the node that is being visited
          ///   - Returns: the rewritten node
          \(node.apiAttributes())\
          open func visit(_ node: \(node.kind.syntaxType)) -> \(node.baseType.syntaxBaseName) {
            return \(node.baseType.syntaxBaseName)(\(node.kind.syntaxType)(unsafeCasting: visitChildren(node._syntaxNode)))
          }
          """
        )
      }
    }

    for baseNode in SYNTAX_NODES
    where baseNode.kind.isBase && baseNode.kind != .syntax && baseNode.kind != .syntaxCollection {
      let baseKind = baseNode.kind
      DeclSyntax(
        """
        /// Visit any \(baseKind.syntaxType) node.
        ///   - Parameter node: the node that is being visited
        ///   - Returns: the rewritten node
        \(baseNode.apiAttributes())\
        public func visit(_ node: \(baseKind.syntaxType)) -> \(baseKind.syntaxType) {
          visitImpl(Syntax(node)).cast(\(baseKind.syntaxType).self)
        }
        """
      )
    }

    // NOTE: '@inline(never)' because perf tests showed the best results.
    // It keeps 'dispatchVisit(_:)' function small, and make all 'case' bodies exactly the same pattern.
    // Which enables some optimizations.
    DeclSyntax(
      """
      @inline(never)
      private func visitTokenSyntaxImpl(_ node: Syntax) -> Syntax {
        Syntax(visit(TokenSyntax(unsafeCasting: node)))
      }
      """
    )

    for node in NON_BASE_SYNTAX_NODES {
      DeclSyntax(
        """
        @inline(never)
        private func visit\(node.kind.syntaxType)Impl(_ node: Syntax) -> Syntax {
          Syntax(visit(\(node.kind.syntaxType)(unsafeCasting: node)))
        }
        """
      )
    }

    try IfConfigDeclSyntax(
      leadingTrivia:
        """
        // SwiftSyntax requires a lot of stack space in debug builds for syntax tree
        // rewriting. In scenarios with reduced stack space (in particular dispatch
        // queues), this easily results in a stack overflow. To work around this issue,
        // use a less performant but also less stack-hungry version of SwiftSyntax's
        // SyntaxRewriter in debug builds.

        """,
      clauses: IfConfigClauseListSyntax {
        IfConfigClauseSyntax(
          poundKeyword: .poundIfToken(),
          condition: ExprSyntax("DEBUG"),
          elements: .statements(
            try CodeBlockItemListSyntax {
              try FunctionDeclSyntax(
                """
                /// Implementation detail of visit(_:). Do not call directly.
                ///
                /// Returns the function that shall be called to visit a specific syntax node.
                ///
                /// To determine the correct specific visitation function for a syntax node,
                /// we need to switch through a huge switch statement that covers all syntax
                /// types. In debug builds, the cases of this switch statement do not share
                /// stack space (rdar://55929175). Because of this, the switch statement
                /// requires about 15KB of stack space. In scenarios with reduced
                /// stack size (in particular dispatch queues), this often results in a stack
                /// overflow during syntax tree rewriting.
                ///
                /// To circumvent this problem, make calling the specific visitation function
                /// a two-step process: First determine the function to call in this function
                /// and return a reference to it, then call it. This way, the stack frame
                /// that determines the correct visitation function will be popped of the
                /// stack before the function is being called, making the switch's stack
                /// space transient instead of having it linger in the call stack.
                private func visitationFunc(for node: Syntax) -> (Syntax) -> Syntax
                """
              ) {
                try SwitchExprSyntax("switch node.raw.kind") {
                  SwitchCaseSyntax("case .token:") {
                    StmtSyntax("return self.visitTokenSyntaxImpl(_:)")
                  }

                  for node in NON_BASE_SYNTAX_NODES {
                    SwitchCaseSyntax("case .\(node.enumCaseCallName):") {
                      StmtSyntax("return self.visit\(node.kind.syntaxType)Impl(_:)")
                    }
                  }
                }
              }

              DeclSyntax(
                """
                private func dispatchVisit(_ node: Syntax) -> Syntax {
                  visitationFunc(for: node)(node)
                }
                """
              )
            }
          )
        )
        IfConfigClauseSyntax(
          poundKeyword: .poundElseToken(),
          elements: .statements(
            CodeBlockItemListSyntax {
              try! FunctionDeclSyntax("private func dispatchVisit(_ node: Syntax) -> Syntax") {
                try SwitchExprSyntax("switch node.raw.kind") {
                  SwitchCaseSyntax("case .token:") {
                    StmtSyntax("return visitTokenSyntaxImpl(node)")
                  }

                  for node in NON_BASE_SYNTAX_NODES {
                    SwitchCaseSyntax("case .\(node.enumCaseCallName):") {
                      StmtSyntax("return visit\(node.kind.syntaxType)Impl(node)")
                    }
                  }
                }
              }
            }
          )
        )
      }
    )

    DeclSyntax(
      """
      private func visitImpl(_ node: Syntax) -> Syntax {
        visitPre(node)
        defer { visitPost(node) }
        return visitAny(node) ?? dispatchVisit(node)
      }
      """
    )

    DeclSyntax(
      """
      private func visitChildren(_ node: Syntax) -> Syntax {
        // Walk over all children of this node and rewrite them. Don't store any
        // rewritten nodes until the first non-`nil` value is encountered. When this
        // happens, retrieve all previous syntax nodes from the parent node to
        // initialize the new layout. Once we know that we have to rewrite the
        // layout, we need to collect all further children, regardless of whether
        // they are rewritten or not.

        // newLayout is nil until the first child node is rewritten and rewritten
        // nodes are being collected.
        var newLayout: UnsafeMutableBufferPointer<RawSyntax?> = .init(start: nil, count: 0)

        // Keep 'RawSyntaxArena' of rewritten nodes alive until they are wrapped
        // with 'Syntax'
        var rewrittens: ContiguousArray<RetainedRawSyntaxArena> = []

        for case let childDataRef? in node.layoutBuffer where viewMode.shouldTraverse(node: childDataRef.pointee.raw) {

          // Build the Syntax node to rewrite
          let childNode = visitImpl(Syntax(arena: node.arena, dataRef: childDataRef))
          if childNode.raw.id != childDataRef.pointee.raw.id {
            // The node was rewritten, let's handle it

            if newLayout.baseAddress == nil {
              // We have not yet collected any previous rewritten nodes. Initialize
              // the new layout with the previous nodes of the parent.
              newLayout = .allocate(capacity: node.raw.layoutView!.children.count)
              _ = newLayout.initialize(fromContentsOf: node.raw.layoutView!.children)
            }

            // Update the rewritten child.
            newLayout[Int(childDataRef.pointee.absoluteInfo.layoutIndexInParent)] = childNode.raw
            // Retain the syntax arena of the new node until it's wrapped with Syntax node.
            rewrittens.append(childNode.raw.arenaReference.retained)
          }
        }

        if newLayout.baseAddress != nil {
          // A child node was rewritten. Build the updated node.

          let rawArena = self.rawArena ?? RawSyntaxArena()
          let newRaw = node.raw.layoutView!.replacingLayout(with: newLayout, arena: rawArena)
          newLayout.deinitialize()
          newLayout.deallocate()
          // 'withExtendedLifetime' to keep 'RawSyntaxArena's of them alive until here.
          return withExtendedLifetime(rewrittens) {
            Syntax(raw: newRaw, rawNodeArena: rawArena)
          }
        } else {
          // No child node was rewritten. So no need to change this node as well.
          return node
        }
      }
      """
    )
  }
}
