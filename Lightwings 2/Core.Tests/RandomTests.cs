using Xunit;

namespace Lightship.Core.Tests
{
    public class RandomTests
    {
        [Fact]
        public void SameSeedSameSequence()
        {
            var a = new DeterministicRandom(42);
            var b = new DeterministicRandom(42);
            for (int i = 0; i < 1000; i++) Assert.Equal(a.NextUlong(), b.NextUlong());
        }

        [Fact]
        public void FloatsStayInUnitInterval()
        {
            var r = new DeterministicRandom(7);
            for (int i = 0; i < 100000; i++)
            {
                float f = r.NextFloat();
                Assert.True(f >= 0f && f < 1f, "out of range: " + f);
            }
        }

        [Fact]
        public void RangeIntIsHalfOpen()
        {
            var r = new DeterministicRandom(3);
            bool sawMin = false, sawMaxMinusOne = false;
            for (int i = 0; i < 10000; i++)
            {
                int v = r.RangeInt(9, 18);
                Assert.InRange(v, 9, 17);
                if (v == 9) sawMin = true;
                if (v == 17) sawMaxMinusOne = true;
            }
            Assert.True(sawMin && sawMaxMinusOne);
        }

        [Fact]
        public void ForkIsIndependentAndDeterministic()
        {
            var a = new DeterministicRandom(11);
            var b = new DeterministicRandom(11);
            var fa = a.Fork(1);
            var fb = b.Fork(1);
            Assert.Equal(fa.NextUlong(), fb.NextUlong());
            Assert.NotEqual(a.NextUlong(), fa.NextUlong());
        }
    }
}
