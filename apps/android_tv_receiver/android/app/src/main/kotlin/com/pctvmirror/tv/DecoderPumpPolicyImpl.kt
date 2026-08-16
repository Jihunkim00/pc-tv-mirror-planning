package com.pctvmirror.tv

import kotlin.collections.ArrayDeque

internal class DecoderAccessUnitQueue<T>(
    private val capacity: Int,
) {
    init {
        require(capacity > 0) { "Decoder access-unit queue capacity must be positive." }
    }

    private val items = ArrayDeque<T>(capacity)

    var maxObservedDepth: Int = 0
        private set

    var overflowCount: Long = 0
        private set

    val size: Int
        get() = items.size

    fun isEmpty(): Boolean = items.isEmpty()

    fun addLast(value: T): Boolean {
        if (items.size >= capacity) {
            recordOverflow()
            return false
        }
        items.addLast(value)
        maxObservedDepth = maxOf(maxObservedDepth, items.size)
        return true
    }

    fun recordOverflow() {
        overflowCount += 1
    }

    fun firstOrNull(): T? = items.firstOrNull()

    operator fun get(index: Int): T = items[index]

    fun removeHeadIf(expected: T): Boolean {
        if (items.firstOrNull() !== expected) {
            return false
        }
        items.removeFirst()
        return true
    }

    fun removeFirst(): T = items.removeFirst()

    fun removeAt(index: Int): T = items.removeAt(index)

    fun indexOfFirst(predicate: (T) -> Boolean): Int = items.indexOfFirst(predicate)

    fun clear() {
        items.clear()
    }

    fun resetDiagnostics() {
        maxObservedDepth = 0
        overflowCount = 0
    }
}

internal class DecoderPumpBudget(
    val maxInputsPerPump: Int = 8,
    val maxOutputsPerPump: Int = 8,
) {
    init {
        require(maxInputsPerPump > 0) { "Decoder input burst limit must be positive." }
        require(maxOutputsPerPump > 0) { "Decoder output burst limit must be positive." }
    }

    var inputsQueued: Int = 0
        private set

    var outputsReleased: Int = 0
        private set

    fun canQueueInput(): Boolean = inputsQueued < maxInputsPerPump

    fun recordInputQueued() {
        check(canQueueInput()) { "Decoder input burst limit exceeded." }
        inputsQueued += 1
    }

    fun canReleaseOutput(): Boolean = outputsReleased < maxOutputsPerPump

    fun recordOutputReleased() {
        check(canReleaseOutput()) { "Decoder output burst limit exceeded." }
        outputsReleased += 1
    }
}
