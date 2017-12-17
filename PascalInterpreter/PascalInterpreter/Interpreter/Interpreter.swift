//
//  Interpreter.swift
//  SwiftPascalInterpreter
//
//  Created by Igor Kulman on 06/12/2017.
//  Copyright © 2017 Igor Kulman. All rights reserved.
//

import Foundation

public class Interpreter {
    private var callStack = Stack<Frame>()
    private let tree: AST
    private let scopes: [String: ScopedSymbolTable]

    public init(_ text: String) {
        let parser = Parser(text)
        tree = parser.parse()
        let semanticAnalyzer = SemanticAnalyzer()
        scopes = semanticAnalyzer.analyze(node: tree)
    }

    @discardableResult private func eval(node: AST) -> Value {
        switch node {
        case let number as Number:
            return eval(number: number)
        case let string as String:
            return eval(string: string)
        case let unaryOperation as UnaryOperation:
            return eval(unaryOperation: unaryOperation)
        case let binaryOperation as BinaryOperation:
            return eval(binaryOperation: binaryOperation)
        case let compound as Compound:
            return eval(compound: compound)
        case let assignment as Assignment:
            return eval(assignment: assignment)
        case let variable as Variable:
            return eval(variable: variable)
        case let block as Block:
            return eval(block: block)
        case let program as Program:
            return eval(program: program)
        case let call as FunctionCall:
            return eval(call: call)
        case let condition as Condition:
            return eval(condition: condition)
        case let ifElse as IfElse:
            return eval(ifElse: ifElse)
        default:
            return .none
        }
    }

    func eval(number: Number) -> Value {
        return .number(number)
    }

    func eval(string: String) -> Value {
        return .string(string)
    }

    func eval(unaryOperation: UnaryOperation) -> Value {
        guard case let .number(result) = eval(node: unaryOperation.operand) else {
            fatalError("Cannot use unary \(unaryOperation.operation) on non number")
        }

        switch unaryOperation.operation {
        case .plus:
            return .number(+result)
        case .minus:
            return .number(-result)
        }
    }
    func eval(binaryOperation: BinaryOperation) -> Value {
        guard case let .number(leftResult) = eval(node: binaryOperation.left), case let .number(rightResult) = eval(node: binaryOperation.right) else {
            fatalError("Cannot use binary \(binaryOperation.operation) on non numbers")
        }

        switch binaryOperation.operation {
        case .plus:
            return .number(leftResult + rightResult)
        case .minus:
            return .number(leftResult - rightResult)
        case .mult:
            return .number(leftResult * rightResult)
        case .integerDiv:
            return .number(leftResult ‖ rightResult)
        case .floatDiv:
            return .number(leftResult / rightResult)
        }
    }

    func eval(compound: Compound) -> Value {
        for child in compound.children {
            eval(node: child)
        }
        return .none
    }

    func eval(assignment: Assignment) -> Value {
        guard let currentFrame = callStack.peek() else {
            fatalError("No call stack frame")
        }

        currentFrame.set(variable: assignment.left.name, value: eval(node: assignment.right))
        return .none
    }

    func eval(variable: Variable) -> Value {
        guard let currentFrame = callStack.peek() else {
            fatalError("No call stack frame")
        }
        return currentFrame.get(variable: variable.name)
    }

    func eval(block: Block) -> Value {
        for declaration in block.declarations {
            eval(node: declaration)
        }

        return eval(node: block.compound)
    }

    func eval(program: Program) -> Value {
        let frame = Frame(scope: scopes["global"]!, previousFrame: nil)
        callStack.push(frame)
        return eval(node: program.block)
    }

    func eval(call: FunctionCall) -> Value {
        let current = callStack.peek()!

        guard let symbol = current.scope.lookup(call.name), symbol is ProcedureSymbol else {
            return callBuiltInProcedure(procedure: call.name, params: call.actualParameters, frame: current)
        }

        let newScope = current.scope.level == 1 ? scopes[call.name]! : ScopedSymbolTable(name: call.name, level: scopes[call.name]!.level + 1, enclosingScope: scopes[call.name]!)
        let frame = Frame(scope: newScope, previousFrame: current)
        callStack.push(frame)
        let result = callFunction(function: call.name, params: call.actualParameters, frame: frame)
        callStack.pop()
        return result
    }

    func eval(condition: Condition) -> Value {
        let left = eval(node: condition.leftSide)
        let right = eval(node: condition.rightSide)

        switch condition.type {
        case .equals:
            return .boolean(left == right)
        case .greaterThan:
            return .boolean(left > right)
        case .lessThan:
            return .boolean(left < right)
        }
    }

    func eval(ifElse: IfElse) -> Value {
        guard case let .boolean(value) = eval(condition: ifElse.condition) else {
            fatalError("Condition not boolean")
        }

        if value {
            return eval(node: ifElse.trueExpression)
        } else if let falseExpression = ifElse.falseExpression {
            return eval(node: falseExpression)
        } else {
            return .none
        }
    }

    private func callFunction(function: String, params: [AST], frame: Frame) -> Value {
        guard let symbol = frame.scope.lookup(function), let procedureSymbol = symbol as? ProcedureSymbol else {
            fatalError("Symbol(procedure) not found '\(function)'")
        }

        if procedureSymbol.params.count > 0 {

            for i in 0 ... procedureSymbol.params.count - 1 {
                let evaluated = eval(node: params[i])
                frame.set(variable: procedureSymbol.params[i].name, value: evaluated)
            }
        }

        eval(node: procedureSymbol.body.block)
        return frame.returnValue
    }

    private func callBuiltInProcedure(procedure: String, params: [AST], frame: Frame) -> Value {
        switch procedure.uppercased() {
        case "WRITE":
            write(params: params, newLine: false)
            return .none
        case "WRITELN":
            write(params: params, newLine: true)
            return .none
        case "READ":
            read(params: params, frame: frame)
            return .none
        default:
            fatalError("Implement built in procedure \(procedure)")
        }
    }

    private func write(params: [AST], newLine: Bool) {
        var s = ""
        for param in params {
            let value = eval(node: param)
            switch value {
            case let .boolean(value):
                s += value ? "TRUE" : "FALSE"
            case let .number(number):
                switch number {
                case let .integer(value):
                    s += String(value)
                case let .real(value):
                    s += String(value)
                }
            case let .string(value):
                s += value
            case .none:
                fatalError("Cannot use WRITE with expression without a value")
            }
        }
        if newLine {
            print(s)
        } else {
            print(s, terminator: "")
        }
    }

    private func read(params: [AST], frame: Frame) {
        guard let line = readLine() else {
            fatalError("Empty input")
        }

        let parts = line.components(separatedBy: CharacterSet.whitespaces)
        for i in 0 ... params.count - 1 {
            let param = params[i]
            guard let variable = param as? Variable else {
                fatalError("READ parameter must be a variable")
            }
            guard let symbol = frame.scope.lookup(variable.name), let variableSymbol = symbol as? VariableSymbol, let type = variableSymbol.type as? BuiltInTypeSymbol else {
                fatalError("Symbol(variable) not found '\(variable.name)'")
            }
            switch type {
            case .integer:
                frame.set(variable: variable.name, value: .number(.integer(Int(parts[i])!)))
            case .real:
                frame.set(variable: variable.name, value: .number(.real(Double(parts[i])!)))
            case .boolean:
                frame.set(variable: variable.name, value: .boolean(Bool(parts[i])!))
            case .string:
                frame.set(variable: variable.name, value: .string((parts[i])))
            }
        }
    }

    public func interpret() {
        eval(node: tree)
    }

    func getState() -> ([String: Int], [String: Double]) {
        return (callStack.peek()!.integerMemory, callStack.peek()!.realMemory)
    }

    public func printState() {
        print("Final interpreter memory state (\(callStack.peek()!.scope.name)):")
        print("Int: \(callStack.peek()!.integerMemory)")
        print("Real: \(callStack.peek()!.realMemory)")
    }
}
