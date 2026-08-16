package com.pctvmirror.tv

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DecoderPumpPolicyTest {
    private data class TestAccessUnit(
        val name: String,
        val ptsUs: Long,
    )

    @Test
    fun fifoOrderAndPtsArePreserved() {
        val queue = DecoderAccessUnitQueue<TestAccessUnit>(4)
        val first = TestAccessUnit("A", 100)
        val second = TestAccessUnit("B", 200)
        val third = TestAccessUnit("C", 300)

        assertTrue(queue.addLast(first))
        assertTrue(queue.addLast(second))
        assertTrue(queue.addLast(third))
        assertTrue(queue.firstOrNull() === first)
        assertEquals(100, queue.firstOrNull()?.ptsUs)

        assertTrue(queue.removeHeadIf(first))
        assertTrue(queue.firstOrNull() === second)
        assertTrue(queue.removeHeadIf(second))
        assertTrue(queue.firstOrNull() === third)
        assertTrue(queue.removeHeadIf(third))
        assertTrue(queue.isEmpty())
    }

    @Test
    fun unavailableInputKeepsTheFifoHead() {
        val queue = DecoderAccessUnitQueue<TestAccessUnit>(4)
        val first = TestAccessUnit("A", 100)
        queue.addLast(first)

        // A failed dequeue does not call removeHeadIf.
        assertTrue(queue.firstOrNull() === first)
        assertEquals(1, queue.size)
    }

    @Test
    fun successfulInputRemovesOnlyTheCommittedHead() {
        val queue = DecoderAccessUnitQueue<TestAccessUnit>(4)
        val first = TestAccessUnit("A", 100)
        val second = TestAccessUnit("B", 200)
        queue.addLast(first)
        queue.addLast(second)

        assertTrue(queue.removeHeadIf(first))
        assertEquals(1, queue.size)
        assertTrue(queue.firstOrNull() === second)
    }

    @Test
    fun pumpBudgetBoundsEachBurst() {
        val budget = DecoderPumpBudget(maxInputsPerPump = 8, maxOutputsPerPump = 8)

        repeat(10) {
            if (budget.canQueueInput()) {
                budget.recordInputQueued()
            }
            if (budget.canReleaseOutput()) {
                budget.recordOutputReleased()
            }
        }

        assertEquals(8, budget.inputsQueued)
        assertEquals(8, budget.outputsReleased)
        assertFalse(budget.canQueueInput())
        assertFalse(budget.canReleaseOutput())
    }

    @Test
    fun overflowRejectsWithoutLatestFrameReplacement() {
        val queue = DecoderAccessUnitQueue<TestAccessUnit>(2)
        val first = TestAccessUnit("A", 100)
        val second = TestAccessUnit("B", 200)
        val latest = TestAccessUnit("C", 300)
        queue.addLast(first)
        queue.addLast(second)

        assertFalse(queue.addLast(latest))
        assertEquals(1, queue.overflowCount)
        assertTrue(queue.firstOrNull() === first)
        assertEquals(2, queue.size)
    }
}
