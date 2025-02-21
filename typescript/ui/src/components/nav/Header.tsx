import Image from 'next/image';
import Link from 'next/link';
import { ConnectWalletButton } from '../../features/wallet/ConnectWalletButton';
import Logo from '../../images/logos/app-logo.svg';
import Name from '../../images/logos/app-name.svg';
import Title from '../../images/logos/app-title.svg';

export function Header() {
  return (
    <header className="w-full px-2 pb-2 pt-3 sm:px-6 lg:px-12">
      <div className="flex items-center justify-between">
        <Link href="/" className="flex items-center py-2">
          <Image src={Logo} height={40} alt="" />
          <Image src={Name} height={30} alt="" className="ml-2 mt-0.5 hidden sm:block" />
          <Image src={Title} height={20} alt="" className="ml-2 mt-0.5 pb-px" />
        </Link>
        <div className="flex flex-col items-end gap-2 md:flex-row-reverse md:items-start">
          <ConnectWalletButton />
        </div>
      </div>
    </header>
  );
}
