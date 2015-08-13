#ifndef __MODEL__
#define __MODEL__

#include <fstream>
#include <iostream>
#include <iomanip>
#include <string>

// Define an class that contains parameters and steady states
struct para {
	// Model parameters
	double bbeta;           //if you don't know beta... good luck
	double ttau;            //search cost
	double aalpha;          //y = z*x*k^aalpha*l^v
	double v;               //labor share
	double ddelta;          //depreciation
	double pphi;            //price of disinvestment relative to investment
	double MC;              //How many units of consumption goods is needed for 1 inv good
	double rrhox;           //persistence of idio TFP
	double ppsi;            //quadratic cost of investment adjustment
	double rrhoz;           //persistence of agg TFP
	double ssigmaz;         //std of z innov
	double ssigmax_low;     //low std of x innov
	double ssigmax_high;    //high std of x innov
	double ppsi_n;          //labor distutility
	double aalpha0;         //efficient coeff of matching
	double aalpha1;         //elasticity of matching
	double eeta;            //adjustment coefficient
	double Pssigmax [4];    //Transition prob of ssigmax

	// Export parameters to a .m file in MATLAB syntax
	__host__
	void exportmatlab(std::string filename) {
		std::ofstream fileout(filename.c_str(), std::ofstream::trunc);
		fileout << std::setprecision(16) << "bbeta=       " << bbeta         << ";"<< std::endl;
		fileout << std::setprecision(16) << "ttau=        " << ttau          << ";"<< std::endl;
		fileout << std::setprecision(16) << "aalpha=      " << aalpha        << ";"<< std::endl;
		fileout << std::setprecision(16) << "v=           " << v             << ";"<< std::endl;
		fileout << std::setprecision(16) << "ddelta=      " << ddelta        << ";"<< std::endl;
		fileout << std::setprecision(16) << "pphi=        " << pphi          << ";"<< std::endl;
		fileout << std::setprecision(16) << "MC=          " << MC            << ";"<< std::endl;
		fileout << std::setprecision(16) << "rrhox=       " << rrhox         << ";"<< std::endl;
		fileout << std::setprecision(16) << "ppsi=        " << ppsi          << ";"<< std::endl;
		fileout << std::setprecision(16) << "rrhoz=       " << rrhoz         << ";"<< std::endl;
		fileout << std::setprecision(16) << "ssigmaz=     " << ssigmaz       << ";"<< std::endl;
		fileout << std::setprecision(16) << "ssigmax_low= " << ssigmax_low   << ";"<< std::endl;
		fileout << std::setprecision(16) << "ssigmax_high=" << ssigmax_high  << ";"<< std::endl;
		fileout << std::setprecision(16) << "ppsi_n=      " << ppsi_n        << ";"<< std::endl;
		fileout << std::setprecision(16) << "aalpha0=     " << aalpha0       << ";"<< std::endl;
		fileout << std::setprecision(16) << "aalpha1=     " << aalpha1       << ";"<< std::endl;
		fileout << std::setprecision(16) << "eeta=        " << eeta          << ";"<< std::endl;
		fileout.close();
	};
};

// Define state struct that contains "natural" state
struct state {
	// Data member
	double k, z, y;
	int i_s,i_q;
};

// Define struct that contains the coefficients on the agg. rules
struct aggrules {
	// Data member
	double pphi_KC;
	double pphi_Kzind;
	double pphi_Kssigmaxind;
	double pphi_Kssigmaxindzind;
	double pphi_KK;
	double pphi_KssigmaxindK;
	double pphi_KzindK;
	double pphi_KssigmaxindzindK;

	double pphi_qC;
	double pphi_qzind;
	double pphi_qssigmaxind;
	double pphi_qssigmaxindzind;
	double pphi_qK;
	double pphi_qssigmaxindK;
	double pphi_qzindK;
	double pphi_qssigmaxindzindK;

	double pphi_CC;
	double pphi_Czind;
	double pphi_Cssigmaxind;
	double pphi_Cssigmaxindzind;
	double pphi_CK;
	double pphi_CssigmaxindK;
	double pphi_CzindK;
	double pphi_CssigmaxindzindK;

	double pphi_mmuC;
	double pphi_mmuzind;
	double pphi_mmussigmaxind;
	double pphi_mmussigmaxindzind;
	double pphi_mmuK;
	double pphi_mmussigmaxindK;
	double pphi_mmuzindK;
	double pphi_mmussigmaxindzindK;
	double pphi_mmuq;

	// savetofile function
	__host__
	void savetofile(std::string filename) {
		std::cout << "================================================================================" << std::endl;
		std::cout << "Saving to " << filename << std::endl;
		std::ofstream fileout(filename.c_str(), std::ofstream::trunc);
		fileout << std::setprecision(16) << pphi_KC << '\n';
		fileout << std::setprecision(16) << pphi_Kzind << '\n';
		fileout << std::setprecision(16) << pphi_Kssigmaxind << '\n';
		fileout << std::setprecision(16) << pphi_Kssigmaxindzind << '\n';
		fileout << std::setprecision(16) << pphi_KK << '\n';
		fileout << std::setprecision(16) << pphi_KssigmaxindK << '\n';
		fileout << std::setprecision(16) << pphi_KzindK << '\n';
		fileout << std::setprecision(16) << pphi_KssigmaxindzindK << '\n';

		fileout << std::setprecision(16) << pphi_qC << '\n';
		fileout << std::setprecision(16) << pphi_qzind << '\n';
		fileout << std::setprecision(16) << pphi_qssigmaxind << '\n';
		fileout << std::setprecision(16) << pphi_qssigmaxindzind << '\n';
		fileout << std::setprecision(16) << pphi_qK << '\n';
		fileout << std::setprecision(16) << pphi_qssigmaxindK << '\n';
		fileout << std::setprecision(16) << pphi_qzindK << '\n';
		fileout << std::setprecision(16) << pphi_qssigmaxindzindK << '\n';

		fileout << std::setprecision(16) << pphi_CC << '\n';
		fileout << std::setprecision(16) << pphi_Czind << '\n';
		fileout << std::setprecision(16) << pphi_Cssigmaxind << '\n';
		fileout << std::setprecision(16) << pphi_Cssigmaxindzind << '\n';
		fileout << std::setprecision(16) << pphi_CK << '\n';
		fileout << std::setprecision(16) << pphi_CssigmaxindK << '\n';
		fileout << std::setprecision(16) << pphi_CzindK << '\n';
		fileout << std::setprecision(16) << pphi_CssigmaxindzindK << '\n';

		fileout << std::setprecision(16) << pphi_mmuC << '\n';
		fileout << std::setprecision(16) << pphi_mmuzind << '\n';
		fileout << std::setprecision(16) << pphi_mmussigmaxind << '\n';
		fileout << std::setprecision(16) << pphi_mmussigmaxindzind << '\n';
		fileout << std::setprecision(16) << pphi_mmuK << '\n';
		fileout << std::setprecision(16) << pphi_mmussigmaxindK << '\n';
		fileout << std::setprecision(16) << pphi_mmuzindK << '\n';
		fileout << std::setprecision(16) << pphi_mmussigmaxindzindK << '\n';
		fileout << std::setprecision(16) << pphi_mmuq << '\n';
		fileout.close();
		std::cout << "Done!" << std::endl;
		std::cout << "================================================================================" << std::endl;
	};

	// load from function
	__host__
	void loadfromfile(std::string filename) {
		std::cout << "================================================================================" << std::endl;
		std::cout << "Loading to " << filename << std::endl;
		std::ifstream filein(filename.c_str());
		filein >> pphi_KC                    ;
		filein >> pphi_Kzind                 ;
		filein >> pphi_Kssigmaxind           ;
		filein >> pphi_Kssigmaxindzind       ;
		filein >> pphi_KK                    ;
		filein >> pphi_KssigmaxindK          ;
		filein >> pphi_KzindK                ;
		filein >> pphi_KssigmaxindzindK      ;

		filein >> pphi_qC                    ;
		filein >> pphi_qzind                 ;
		filein >> pphi_qssigmaxind           ;
		filein >> pphi_qssigmaxindzind       ;
		filein >> pphi_qK                    ;
		filein >> pphi_qssigmaxindK          ;
		filein >> pphi_qzindK                ;
		filein >> pphi_qssigmaxindzindK      ;

		filein >> pphi_CC                    ;
		filein >> pphi_Czind                 ;
		filein >> pphi_Cssigmaxind           ;
		filein >> pphi_Cssigmaxindzind       ;
		filein >> pphi_CK                    ;
		filein >> pphi_CssigmaxindK          ;
		filein >> pphi_CzindK                ;
		filein >> pphi_CssigmaxindzindK      ;

		filein >> pphi_mmuC               ;
		filein >> pphi_mmuzind            ;
		filein >> pphi_mmussigmaxind      ;
		filein >> pphi_mmussigmaxindzind  ;
		filein >> pphi_mmuK               ;
		filein >> pphi_mmussigmaxindK     ;
		filein >> pphi_mmuzindK           ;
		filein >> pphi_mmussigmaxindzindK ;
		filein >> pphi_mmuq               ;

		filein.close();
		std::cout << "Done!" << std::endl;
		std::cout << "================================================================================" << std::endl;
	};
};

#endif
