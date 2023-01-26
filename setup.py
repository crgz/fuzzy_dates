import pathlib
from setuptools import setup, find_packages

# The directory containing this file
HERE = pathlib.Path(__file__).parent

# The text of the README file
README = (HERE / "README.md").read_text()

# This call to setup() does all the work
setup(
    name="fuzzy_parser",
    version="0.2.59",
    description="A parser for fuzzy dates",
    long_description=README,
    long_description_content_type="text/markdown",
    url="https://github.com/crgz/fuzzy_dates",
    author="Real Python",
    author_email="conrado.rgz@gmail.com",
    license="MIT",
    classifiers=[
        "License :: OSI Approved :: MIT License",
        "Programming Language :: Python :: 3",
        "Programming Language :: Python :: 3.7",
    ],
    packages=find_packages(exclude=("tests",)),
    include_package_data=True,
    install_requires=["pytest", "pyswip"],
    entry_points={
        "console_scripts": [
            "fuzzy_parser=fuzzy_parser.__main__:main",
        ]
    }
)
