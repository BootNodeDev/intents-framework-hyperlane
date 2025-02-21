import type { NextPage } from 'next';
import { useRouter } from 'next/router';

const Home: NextPage = () => {
  const { reload } = useRouter();
  return (
    <div className="space-y-3 pt-4">
      <div className="relative">
        <div className="rounded-lg bg-white p-8 text-center shadow-md">
          <h1 className="mb-4 text-3xl">We&apos;ll be back soon!</h1>
          <p className="mb-6 text-lg">We are currently undergoing scheduled maintenance.</p>
          <p className="mb-6 text-lg">Please refresh the page or check back later.</p>
          <button
            className="cursor-pointer rounded bg-blue-500 px-6 py-3 text-base text-white hover:bg-blue-700"
            onClick={reload}
          >
            Refresh
          </button>
        </div>{' '}
      </div>
    </div>
  );
};

export default Home;
