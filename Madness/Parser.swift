//  Copyright (c) 2014 Rob Rix. All rights reserved.

/// Convenience for describing the types of parser combinators.
///
/// \param Tree  The type of parse tree generated by the parser.
public enum Parser<C: CollectionType, Tree> {
	/// The type of parser combinators.
	public typealias Function = (C, SourcePos<C.Index>) -> Result

	/// The type produced by parser combinators.
	public typealias Result = Either<Error<C.Index>, (Tree, SourcePos<C.Index>)>
}

/// Parses `input` with `parser`, returning the parse trees or `nil` if nothing could be parsed, or if parsing did not consume the entire input.
public func parse<C: CollectionType, Tree>(parser: Parser<C, Tree>.Function, input: C) -> Either<Error<C.Index>, Tree> {
	let result = parser(input, SourcePos(index: input.startIndex))
	
	return result.flatMap { tree, sourcePos in
		return sourcePos.index == input.endIndex
			? .Right(tree)
			: .Left(.leaf("finished parsing before end of input", sourcePos))
	}
}

public func parse<Tree>(parser: Parser<String.CharacterView, Tree>.Function, input: String) -> Either<Error<String.Index>, Tree> {
	return parse(parser, input: input.characters)
}

// MARK: - Terminals

/// Returns a parser which never parses its input.
public func none<C: CollectionType, Tree>(string: String = "no way forward") -> Parser<C, Tree>.Function {
	return { _, sourcePos in Either.left(Error.leaf(string, sourcePos)) }
}

// Returns a parser which parses any single character.
public func any<C: CollectionType>(input: C, sourcePos: SourcePos<C.Index>) -> Parser<C, C.Generator.Element>.Result {
	return satisfy { _ in true }(input, sourcePos)
}

public func any(input: String.CharacterView, sourcePos: SourcePos<String.Index>) -> Parser<String.CharacterView, Character>.Result {
	return satisfy { _ in true }(input, sourcePos)
}


/// Returns a parser which parses a `literal` sequence of elements from the input.
///
/// This overload enables e.g. `%"xyz"` to produce `String -> (String, String)`.
public prefix func % <C: CollectionType where C.Generator.Element: Equatable> (literal: C) -> Parser<C, C>.Function {
	return { input, sourcePos in
		if containsAt(input, index: sourcePos.index, needle: literal) {
			return .Right(literal, updateIndex(sourcePos, sourcePos.index.advancedBy(literal.count)))
		} else {
			return .Left(.leaf("expected \(literal)", sourcePos))
		}
	}
}

public prefix func %(literal: String) -> Parser<String.CharacterView, String>.Function {
	return { input, sourcePos in
		if containsAt(input, index: sourcePos.index, needle: literal.characters) {
			return .Right(literal, updatePosString(sourcePos, literal))
		} else {
			return .Left(.leaf("expected \(literal)", sourcePos))
		}
	}
}

/// Returns a parser which parses a `literal` element from the input.
public prefix func % <C: CollectionType where C.Generator.Element: Equatable> (literal: C.Generator.Element) -> Parser<C, C.Generator.Element>.Function {
	return { input, sourcePos in
		if sourcePos.index != input.endIndex && input[sourcePos.index] == literal {
			return .Right((literal, updateIndex(sourcePos, sourcePos.index.successor())))
		} else {
			return .Left(.leaf("expected \(literal)", sourcePos))
		}
	}
}


/// Returns a parser which parses any character in `interval`.
public prefix func %<I: IntervalType where I.Bound == Character>(interval: I) -> Parser<String.CharacterView, String>.Function {
	return { (input: String.CharacterView, sourcePos: SourcePos<String.Index>) in
		let index = sourcePos.index
		
		if index < input.endIndex && interval.contains(input[index]) {
			let string = String(input[index])
			return .Right((string, updateIndex(sourcePos, index.successor())))
		} else {
			return .Left(.leaf("expected an element in interval \(interval)", sourcePos))
		}
	}
}


// MARK: - Nonterminals

private func memoize<T>(f: () -> T) -> () -> T {
	var memoized: T!
	return {
		if memoized == nil {
			memoized = f()
		}
		return memoized
	}
}

public func delay<C: CollectionType, T>(parser: () -> Parser<C, T>.Function) -> Parser<C, T>.Function {
	let memoized = memoize(parser)
	return { memoized()($0, $1) }
}


// MARK: - Private

/// Returns `true` iff `collection` contains all of the elements in `needle` in-order and contiguously, starting from `index`.
func containsAt<C1: CollectionType, C2: CollectionType where C1.Generator.Element == C2.Generator.Element, C1.Generator.Element: Equatable>(collection: C1, index: C1.Index, needle: C2) -> Bool {
	let needleCount = needle.count.toIntMax()
	let range = index..<index.advancedBy(C1.Index.Distance(needleCount), limit: collection.endIndex)
	if range.count.toIntMax() < needleCount { return false }

	return zip(range, needle).lazy.map { collection[$0] == $1 }.reduce(true) { $0 && $1 }
}

// Returns a parser that satisfies the given predicate
public func satisfy(pred: Character -> Bool) -> Parser<String.CharacterView, Character>.Function {
	return tokenPrim(updatePosCharacter, pred)
}

// Returns a parser that satisfies the given predicate
public func satisfy<C: CollectionType> (pred: C.Generator.Element -> Bool) -> Parser<C, C.Generator.Element>.Function {
	return tokenPrim({ oldPos, el in
		updateIndex(oldPos, oldPos.index.advancedBy(1))
	}, pred)
}

public func tokenPrim<C: CollectionType> (nextPos: (SourcePos<C.Index>, C.Generator.Element) -> SourcePos<C.Index>, _ pred: C.Generator.Element -> Bool) -> Parser<C, C.Generator.Element>.Function {
	return { input, sourcePos in
		let index = sourcePos.index
		if index != input.endIndex {
			let parsed = input[index]
			
			if pred(parsed) {
				return .Right((parsed, nextPos(sourcePos, parsed)))
			} else {
				return .Left(Error.leaf("Failed to parse \(String(parsed)) with predicate at index", sourcePos))
			}
		} else {
			return .Left(Error.leaf("Failed to parse at end of input", sourcePos))
		}
	}
}


// MARK: - Operators

/// Map operator.
infix operator --> {
	/// Associates to the left.
	associativity left

	/// Lower precedence than |.
	precedence 100
}


/// Literal operator.
prefix operator % {}


// MARK: - Imports

import Either
import Prelude
